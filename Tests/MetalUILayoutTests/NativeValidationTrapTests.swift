import Testing
import MetalUICore
import MetalUILayout

// Lane 3 ("robustness") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`:
// what the proposal kernel REJECTS, ruling SA-J in
// `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`.
//
// **The rule.** A parameter is rejected only if SwiftUI rejects it (a
// diagnostic, a trap, a hang, or no spelling), or if it would make the node's
// measurement, or a rect it places, non-finite at a proposal with no infinite
// axis. Computed values meet three checkpoints: a NaN proposal at
// `measureNative` entry, a NaN measurement at its exit, and a non-finite rect
// at `placeNative` entry. The SwiftUI answer behind each row is the probe arm
// named in SA-J's table (`docs/probes/swiftui-layout-input-validation.swift`
// and `swiftui-layout-protocol-contract.swift`).
//
// **A plain import**: every registrar and entry point touched here is public,
// so these are the traps an outside module meets.
//
// **One exit test per rejected arm**, because exit-test bodies cannot capture,
// and each asserts its parameter's message fragment on stderr as well as the
// failure, so a trap elsewhere cannot pass. What is ACCEPTED lives in
// `NativeValidationAcceptanceTests.swift`, as exit `.success` tests.

private struct Trap {
    static func stderr(_ result: ExitTest.Result?) -> String {
        String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    }
}

/// A custom layout driven by two closures, for the checkpoint arms whose
/// layout is the fixture.
private struct ScriptedLayout: ProposalLayout {
    var measure: @Sendable (ProposedSize, MeasurementSubviews) -> LayoutMeasurement
    var place: @Sendable (LayoutRect, ProposedSize, PlacementSubviews) -> Void

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        measure(proposal, subviews)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        place(bounds, proposal, subviews)
    }
}

// MARK: - Stack spacing: `isFinite` (P1, P9)

/// SwiftUI answers `nan` for a NaN spacing (P1).
@Test func aNaNStackSpacingTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeLinearStack(children: [leaf], axis: .horizontal, spacing: .nan)
    }
    #expect(Trap.stderr(result).contains("linear stack spacing must be finite"),
            "aborted, but not at the spacing check:\n\(Trap.stderr(result))")
}

/// SwiftUI answers `inf` (P1).
@Test func anInfiniteStackSpacingTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeLinearStack(children: [leaf], axis: .horizontal, spacing: .infinity)
    }
    #expect(Trap.stderr(result).contains("linear stack spacing must be finite"),
            "aborted, but not at the spacing check:\n\(Trap.stderr(result))")
}

/// SwiftUI answers `-inf` (P9). With the NaN arm, the witness that the rule is
/// `isFinite` and not `!= .infinity`.
@Test func aNegativeInfiniteStackSpacingTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeLinearStack(children: [leaf], axis: .vertical, spacing: -.infinity)
    }
    #expect(Trap.stderr(result).contains("linear stack spacing must be finite"),
            "aborted, but not at the spacing check:\n\(Trap.stderr(result))")
}

// MARK: - Padding insets: `isFinite` (P2, P2c, P9)

/// SwiftUI answers 0×0 and then traps placing the child (P2c).
@Test func aNaNPaddingInsetTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativePadding(child: leaf, insets: Edges(top: 0, right: 0, bottom: .nan, left: 0))
    }
    #expect(Trap.stderr(result).contains("padding insets must be finite"),
            "aborted, but not at the padding check:\n\(Trap.stderr(result))")
}

/// SwiftUI answers inf×inf (P2).
@Test func anInfinitePaddingInsetTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativePadding(child: leaf, insets: Edges(top: .infinity, right: 0, bottom: 0, left: 0))
    }
    #expect(Trap.stderr(result).contains("padding insets must be finite"),
            "aborted, but not at the padding check:\n\(Trap.stderr(result))")
}

/// SwiftUI answers 0×0 and places the child at −∞ (P9, P2c).
@Test func aNegativeInfinitePaddingInsetTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativePadding(child: leaf, insets: Edges(top: 0, right: 0, bottom: 0, left: -.infinity))
    }
    #expect(Trap.stderr(result).contains("padding insets must be finite"),
            "aborted, but not at the padding check:\n\(Trap.stderr(result))")
}

// MARK: - Fixed frame dimension: `>= 0 && isFinite` (P3, P9)
//
// No −∞ arm: both halves reject it, so it could not tell a mutation of either
// half. NaN is also rejected by both halves; its own mutation is the NaN-blind
// spelling `!(x < 0) && x != .infinity`.

/// SwiftUI logs "Invalid frame dimension" (P3).
@Test func aNegativeFixedFrameDimensionTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, width: -10)
    }
    #expect(Trap.stderr(result).contains("frame width must be finite and non-negative"),
            "aborted, but not at the fixed-dimension check:\n\(Trap.stderr(result))")
}

@Test func aNaNFixedFrameDimensionTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, height: .nan)
    }
    #expect(Trap.stderr(result).contains("frame height must be finite and non-negative"),
            "aborted, but not at the fixed-dimension check:\n\(Trap.stderr(result))")
}

@Test func anInfiniteFixedFrameDimensionTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, width: .infinity)
    }
    #expect(Trap.stderr(result).contains("frame width must be finite and non-negative"),
            "aborted, but not at the fixed-dimension check:\n\(Trap.stderr(result))")
}

// MARK: - Frame minimum: `!isNaN && != +∞` (P4, P4b); −10 and −∞ are accepted

@Test func aNaNFrameMinimumTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, minWidth: .nan)
    }
    #expect(Trap.stderr(result).contains("frame minWidth must not be NaN or +infinity"),
            "aborted, but not at the minimum check:\n\(Trap.stderr(result))")
}

@Test func anInfiniteFrameMinimumTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, minHeight: .infinity)
    }
    #expect(Trap.stderr(result).contains("frame minHeight must not be NaN or +infinity"),
            "aborted, but not at the minimum check:\n\(Trap.stderr(result))")
}

// MARK: - Frame maximum: `>= 0` (P4, P4c, P9); +∞ is accepted
//
// `>= 0` is false for NaN, so the rule needs no `!isNaN` clause. The NaN arm's
// own mutation is the NaN-blind spelling `!(maximum < 0)`.

@Test func aNegativeFrameMaximumTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, maxWidth: -10)
    }
    #expect(Trap.stderr(result).contains("frame maxWidth must be non-negative"),
            "aborted, but not at the maximum check:\n\(Trap.stderr(result))")
}

@Test func aNaNFrameMaximumTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, maxHeight: .nan)
    }
    #expect(Trap.stderr(result).contains("frame maxHeight must be non-negative"),
            "aborted, but not at the maximum check:\n\(Trap.stderr(result))")
}

// MARK: - Frame ideal: `>= 0 && isFinite` (P4b, P4d)
//
// +∞ is rejected by clause 2: SwiftUI gives no diagnostic, but answers ∞ at the
// unspecified proposal every stack child receives on its main axis (P4b).

@Test func aNegativeFrameIdealTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, idealWidth: -10)
    }
    #expect(Trap.stderr(result).contains("frame idealWidth must be finite and non-negative"),
            "aborted, but not at the ideal check:\n\(Trap.stderr(result))")
}

@Test func aNaNFrameIdealTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, idealHeight: .nan)
    }
    #expect(Trap.stderr(result).contains("frame idealHeight must be finite and non-negative"),
            "aborted, but not at the ideal check:\n\(Trap.stderr(result))")
}

@Test func anInfiniteFrameIdealTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, idealWidth: .infinity)
    }
    #expect(Trap.stderr(result).contains("frame idealWidth must be finite and non-negative"),
            "aborted, but not at the ideal check:\n\(Trap.stderr(result))")
}

// MARK: - Frame ordering and combination (P4, P4c; no SwiftUI spelling combines)

/// SwiftUI logs "Contradictory frame constraints" (P4).
@Test func aFrameMinimumAboveItsMaximumTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, minWidth: 50, maxWidth: 40)
    }
    #expect(Trap.stderr(result).contains("frame minWidth must not exceed maxWidth"),
            "aborted, but not at the min/max ordering check:\n\(Trap.stderr(result))")
}

@Test func aFrameMinimumAboveItsIdealTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, minHeight: 50, idealHeight: 40)
    }
    #expect(Trap.stderr(result).contains("frame minHeight must not exceed idealHeight"),
            "aborted, but not at the min/ideal ordering check:\n\(Trap.stderr(result))")
}

/// SwiftUI logs "Contradictory frame constraints" and answers the ideal (P4c).
@Test func aFrameIdealAboveItsMaximumTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, idealWidth: 90, maxWidth: 80)
    }
    #expect(Trap.stderr(result).contains("frame idealWidth must not exceed maxWidth"),
            "aborted, but not at the ideal/max ordering check:\n\(Trap.stderr(result))")
}

/// The kernel registrar keeps one signature, so it can spell a fixed and a
/// flexible dimension on one axis; SwiftUI has no overload that can
/// (`extra argument 'minWidth' in call`). The element API cannot spell it
/// either, pinned by the typecheck guard
/// `aFixedAndAFlexibleFrameDimensionCannotBeCombined`; this is the backstop.
@Test func aFixedFrameDimensionCombinedWithAFlexibleOneTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeFrame(child: leaf, width: 10, minWidth: 5)
    }
    #expect(Trap.stderr(result).contains("frame width cannot be combined with minWidth, idealWidth or maxWidth"),
            "aborted, but not at the fixed/flexible combination check:\n\(Trap.stderr(result))")
}

// MARK: - Spacer minimum: `isFinite` (P5, P9); a negative minimum is accepted

/// SwiftUI answers `-inf` for a NaN minimum length (P5).
@Test func aNaNSpacerMinimumTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        _ = tree.newNativeSpacer(minLength: .nan)
    }
    #expect(Trap.stderr(result).contains("spacer minLength must be finite"),
            "aborted, but not at the spacer check:\n\(Trap.stderr(result))")
}

@Test func anInfiniteSpacerMinimumTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        _ = tree.newNativeSpacer(minLength: .infinity)
    }
    #expect(Trap.stderr(result).contains("spacer minLength must be finite"),
            "aborted, but not at the spacer check:\n\(Trap.stderr(result))")
}

@Test func aNegativeInfiniteSpacerMinimumTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        _ = tree.newNativeSpacer(minLength: -.infinity)
    }
    #expect(Trap.stderr(result).contains("spacer minLength must be finite"),
            "aborted, but not at the spacer check:\n\(Trap.stderr(result))")
}

// MARK: - Layout priority: `!isNaN` (P7); ±∞ is accepted

/// SwiftUI hangs on a NaN priority (P7 `--include-hang`: 99.4% CPU at 00:20,
/// killed). The old `isFinite` rule already trapped on NaN, under the message
/// "layout priority must be finite", so before this lane the test failed on
/// its fragment alone; the rule's own red run is the mutation "delete the
/// precondition".
@Test func aNaNLayoutPriorityTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeLayoutPriority(child: leaf, priority: .nan)
    }
    #expect(Trap.stderr(result).contains("layout priority must not be NaN"),
            "aborted, but not at the priority check:\n\(Trap.stderr(result))")
}

// MARK: - Aspect ratio: `isFinite && != 0` (P8, P9); a negative ratio is accepted

/// 0 is finite on a two-axis proposal and answers 0×inf on a one-axis one (P8).
/// The old rule (`isFinite && > 0`) already trapped here, under the message
/// "…greater than zero", so before this lane the four ratio arms failed on
/// their fragment alone. The rule's own red runs are mutations: `ratio != 0`
/// alone keeps this arm green and reddens the NaN and +∞ arms.
@Test func aZeroAspectRatioTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeAspectRatio(child: leaf, ratio: 0)
    }
    #expect(Trap.stderr(result).contains("aspect ratio must be finite and non-zero"),
            "aborted, but not at the ratio check:\n\(Trap.stderr(result))")
}

/// SwiftUI answers nan×nan (P8). Red before on its fragment only, as above.
@Test func aNaNAspectRatioTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeAspectRatio(child: leaf, ratio: .nan)
    }
    #expect(Trap.stderr(result).contains("aspect ratio must be finite and non-zero"),
            "aborted, but not at the ratio check:\n\(Trap.stderr(result))")
}

/// SwiftUI answers nan×0 (P8). Red before on its fragment only, as above.
@Test func anInfiniteAspectRatioTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeAspectRatio(child: leaf, ratio: .infinity)
    }
    #expect(Trap.stderr(result).contains("aspect ratio must be finite and non-zero"),
            "aborted, but not at the ratio check:\n\(Trap.stderr(result))")
}

/// SwiftUI answers nan×−0 (P9). Red before on its fragment only; the mutation
/// `!ratio.isNaN && ratio != .infinity` reddens it.
@Test func aNegativeInfiniteAspectRatioTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        _ = tree.newNativeAspectRatio(child: leaf, ratio: -.infinity)
    }
    #expect(Trap.stderr(result).contains("aspect ratio must be finite and non-zero"),
            "aborted, but not at the ratio check:\n\(Trap.stderr(result))")
}

// MARK: - Checkpoint 1: a NaN proposal at `measureNative` entry (P6)

/// SwiftUI echoes a NaN proposal back as a NaN size (P6). NaN is unequal to
/// itself, so it would also miss the measurement cache every time.
@Test func aNaNRootProposalTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        tree.computeNativeLayout(root: leaf, proposal: ProposedSize(width: .nan, height: 10),
                                 in: LayoutRect(x: 0, y: 0, width: 20, height: 20))
    }
    #expect(Trap.stderr(result).contains("received a NaN proposal"),
            "aborted, but not at checkpoint 1:\n\(Trap.stderr(result))")
}

/// The same checkpoint catches a NaN a custom layout asks a subview at.
@Test func aNaNSubviewProposalTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        let layout = ScriptedLayout(
            measure: { _, subviews in
                _ = subviews[0].sizeThatFits(ProposedSize(width: 10, height: .nan))
                return LayoutMeasurement(size: SizeD(width: 20, height: 20))
            },
            place: { _, _, _ in })
        let root = tree.newNativeLayout(layout, children: [leaf])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
    }
    #expect(Trap.stderr(result).contains("received a NaN proposal"),
            "aborted, but not at checkpoint 1:\n\(Trap.stderr(result))")
}

// MARK: - Checkpoint 2: a NaN measurement at `measureNative` exit (N)

/// SwiftUI accepts a child's NaN answer and places it at (nan, …) (N).
@Test func aNaNMeasurementTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: .nan, height: 20)) }
        tree.computeNativeLayout(root: leaf, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
    }
    #expect(Trap.stderr(result).contains("produced a NaN measurement"),
            "aborted, but not at checkpoint 2:\n\(Trap.stderr(result))")
}

/// The same checkpoint catches a custom `sizeThatFits` answering a NaN baseline.
@Test func aNaNCustomMeasurementTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        let layout = ScriptedLayout(
            measure: { _, _ in LayoutMeasurement(size: SizeD(width: 20, height: 20), firstBaseline: .nan) },
            place: { _, _, _ in })
        let root = tree.newNativeLayout(layout, children: [leaf])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
    }
    #expect(Trap.stderr(result).contains("produced a NaN measurement"),
            "aborted, but not at checkpoint 2:\n\(Trap.stderr(result))")
}

// MARK: - Checkpoint 3: a non-finite rect at `placeNative` entry (M, N)

/// Root bounds are placed as given, so a non-finite root rect is caught here.
@Test func aNonFiniteRootBoundsTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        tree.computeNativeLayout(root: leaf, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: .infinity, width: 100, height: 100))
    }
    #expect(Trap.stderr(result).contains("non-finite rect"),
            "aborted, but not at checkpoint 3:\n\(Trap.stderr(result))")
}

/// A measurement may be infinite; a stored rect may not. A custom layout
/// places a proposal-echoing leaf at an ∞ proposal: its ∞ answer passes
/// checkpoint 2 and becomes an ∞-wide rect at checkpoint 3. SwiftUI stores
/// such a child at (−inf, 95, inf, 10) (N).
@Test func anInfiniteStoredRectTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
        }
        let layout = ScriptedLayout(
            measure: { _, _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) },
            place: { bounds, _, subviews in
                subviews[0].place(at: Point(x: bounds.x, y: bounds.y),
                                  proposal: ProposedSize(width: .infinity, height: 10))
            })
        let root = tree.newNativeLayout(layout, children: [leaf])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
    }
    #expect(Trap.stderr(result).contains("non-finite rect"),
            "aborted, but not at checkpoint 3:\n\(Trap.stderr(result))")
}

/// A custom layout placing a greedy frame at an ∞ proposal traps at
/// checkpoint 3 (ruling CN-F, containers lane 2's test 2.4). Since CN-F a
/// `.frame(maxWidth: .infinity)` over a fixed 20pt child answers ∞ at ∞, as
/// SwiftUI's does, so its stored rect would be ∞ wide: SwiftUI crashes placing
/// that answer (`swiftui-frame-semantics.swift` D12's recorded "view origin is
/// invalid", reproduced by `swiftui-stack-algorithms.swift` K4f's first run).
/// `anInfiniteStoredRectTraps` above is the same checkpoint reached by a
/// proposal-echoing leaf; this is the frame, which answered its child (20)
/// under FR-B and so did not trap before the lane. Mutation: remove checkpoint
/// 3's width term.
@Test func aCustomLayoutPlacingAChildAtAnInfiniteProposalTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        let frame = tree.newNativeFrame(child: leaf, maxWidth: .infinity)
        let layout = ScriptedLayout(
            measure: { _, _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) },
            place: { bounds, _, subviews in
                subviews[0].place(at: Point(x: bounds.x, y: bounds.y),
                                  proposal: ProposedSize(width: .infinity, height: 10))
            })
        let root = tree.newNativeLayout(layout, children: [frame])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
    }
    #expect(Trap.stderr(result).contains("non-finite rect"),
            "aborted, but not at checkpoint 3:\n\(Trap.stderr(result))")
}

/// SwiftUI accepts a +∞ placement position and stores (inf, 0, 20, 20) (M).
@Test func aNonFinitePlacementPositionTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        let layout = ScriptedLayout(
            measure: { _, _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) },
            place: { _, _, subviews in
                subviews[0].place(at: Point(x: .infinity, y: 0),
                                  proposal: ProposedSize(width: 20, height: 20))
            })
        let root = tree.newNativeLayout(layout, children: [leaf])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
    }
    #expect(Trap.stderr(result).contains("non-finite rect"),
            "aborted, but not at checkpoint 3:\n\(Trap.stderr(result))")
}
