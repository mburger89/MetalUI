import Testing
import MetalUICore
import MetalUILayout

// Lane 3 ("robustness") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`:
// what the proposal kernel ACCEPTS, and the answer it must give. Rulings SA-J
// (the validation policy) and SA-K (the relaxations and repairs it forces) in
// `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`. Every expected
// number is SwiftUI's, from `docs/probes/swiftui-layout-input-validation.swift`
// (arm in each doc comment), re-derived here through the kernel's arithmetic.
//
// **Every test is an exit `.success` test, with `precondition`s on the
// values.** The mutation that must redden each one is a REJECTION: in-process,
// that trap would abort the whole `MetalUILayoutTests` process and truncate the
// suite instead of reddening one test (practices shapes 11 and 13).

// MARK: - Stack spacing (P1, P9)

/// SwiftUI answers `{20; 20}` at spacing −10 with 30, and at −100 with −60,
/// **unclamped**, both at an unspecified proposal and at a 50 proposal (P1).
/// Green on arrival; red under "reject negative spacing" or "clamp gaps at 0"
/// (which reads 40).
@Test func negativeStackSpacingAnswersSwiftUIsUnclampedSum() async {
    await #expect(processExitsWith: .success) {
        func width(spacing: Double, proposal: ProposedSize) -> Double {
            let tree = LayoutTree(generation: 0)
            let a = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
            let b = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
            let stack = tree.newNativeLinearStack(children: [a, b], axis: .horizontal, spacing: spacing)
            return tree.computeNativeLayout(root: stack, proposal: proposal,
                                            in: LayoutRect(x: 0, y: 0, width: 50, height: 20)).size.width
        }
        let small = width(spacing: -10, proposal: .unspecified)
        precondition(small == 30, "spacing −10 answered \(small), SwiftUI 30")
        let large = width(spacing: -100, proposal: .unspecified)
        precondition(large == -60, "spacing −100 at nil answered \(large), SwiftUI −60")
        let offered = width(spacing: -100, proposal: ProposedSize(width: 50, height: nil))
        precondition(offered == -60, "spacing −100 at 50 answered \(offered), SwiftUI −60")
    }
}

// MARK: - Padding (P2, P2b, P9)

/// SwiftUI accepts negative padding and **clamps its response at 0 per axis**
/// (P2, P2b), ruling SA-K item 3:
/// - −5 all round on a fixed 20×20 child answers 10×10;
/// - −15 answers 0×0, where the unclamped kernel answered −10;
/// - leading −30 / trailing 5 answers 0×20: the clamp is per axis;
/// - −5 on a proposal-filling child offered 100×100 answers 100×100
///   (the child is offered 110 and answers it).
///
/// Placement: the child's stored origin is the padding's origin plus its
/// leading and top insets, as SwiftUI places it (P2b). The padding is laid out
/// at bounds (40, 50) with its own clamped answer as the size, so the −15 child
/// lands at (25, 35) and the leading −30 child at x 10.
///
/// **The child's stored WIDTH is pinned wrong on purpose.** The kernel stores a
/// padded child at the padding's bounds minus its insets: 0 + 15 + 15 = 30 for
/// −15 on 20, where SwiftUI keeps the child at its own 20 (P2b). That is ruling
/// SA-N item 4, plan task 5's; when task 5 fixes it, this arm reddens
/// deliberately and must be re-derived, not deleted.
@Test func negativePaddingIsAcceptedAndItsResponseClampsPerAxis() async {
    await #expect(processExitsWith: .success) {
        func fixed(_ tree: LayoutTree) -> LayoutNodeID {
            tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        }

        let small = LayoutTree(generation: 0)
        let smallPadding = small.newNativePadding(child: fixed(small), insets: Edges(all: -5))
        let smallSize = small.computeNativeLayout(root: smallPadding, proposal: .unspecified,
                                                  in: LayoutRect(x: 0, y: 0, width: 10, height: 10)).size
        precondition(smallSize == SizeD(width: 10, height: 10), "−5 on 20 answered \(smallSize), SwiftUI 10×10")

        let clamped = LayoutTree(generation: 0)
        let clampedChild = fixed(clamped)
        let clampedPadding = clamped.newNativePadding(child: clampedChild, insets: Edges(all: -15))
        let clampedSize = clamped.computeNativeLayout(root: clampedPadding, proposal: .unspecified,
                                                      in: LayoutRect(x: 40, y: 50, width: 0, height: 0)).size
        precondition(clampedSize == SizeD(width: 0, height: 0), "−15 on 20 answered \(clampedSize), SwiftUI 0×0")
        let clampedRect = clamped.layout(clampedChild)
        precondition(clampedRect.x == 25 && clampedRect.y == 35,
                     "−15 child stored at \(clampedRect), SwiftUI's origin is (25, 35)")
        // Pinned wrong on purpose (SA-N item 4): SwiftUI's width is 20.
        precondition(clampedRect.width == 30 && clampedRect.height == 30,
                     "−15 child stored at \(clampedRect); today's bounds-minus-insets size is 30×30")

        let lopsided = LayoutTree(generation: 0)
        let lopsidedChild = fixed(lopsided)
        let lopsidedPadding = lopsided.newNativePadding(child: lopsidedChild,
                                                        insets: Edges(top: 0, right: 5, bottom: 0, left: -30))
        let lopsidedSize = lopsided.computeNativeLayout(root: lopsidedPadding, proposal: .unspecified,
                                                        in: LayoutRect(x: 40, y: 50, width: 0, height: 20)).size
        precondition(lopsidedSize == SizeD(width: 0, height: 20),
                     "leading −30 / trailing 5 on 20 answered \(lopsidedSize), SwiftUI 0×20")
        let lopsidedRect = lopsided.layout(lopsidedChild)
        precondition(lopsidedRect.x == 10 && lopsidedRect.y == 50,
                     "leading −30 child stored at \(lopsidedRect), SwiftUI's origin is (10, 50)")

        let filling = LayoutTree(generation: 0)
        let echo = filling.newNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
        }
        let fillingPadding = filling.newNativePadding(child: echo, insets: Edges(all: -5))
        let fillingSize = filling.computeNativeLayout(root: fillingPadding,
                                                      proposal: ProposedSize(width: 100, height: 100),
                                                      in: LayoutRect(x: 0, y: 0, width: 100, height: 100)).size
        precondition(fillingSize == SizeD(width: 100, height: 100),
                     "−5 on a filling child offered 100 answered \(fillingSize), SwiftUI 100×100")
    }
}

// MARK: - Frame minimum and maximum (P4, P4b, P4c, P9)

/// SwiftUI accepts `minWidth` −10 and −∞ with no diagnostic: both answer the
/// 20pt child's 20 at a 100 proposal (P4, P9). `maxWidth` +∞ answers 100 at a
/// 100 proposal and the child's 20 at an unspecified one (P4c). Green on
/// arrival; red under "reject a negative minimum".
@Test func negativeAndNegativeInfiniteFrameMinimumsAndAnInfiniteMaximumAreAccepted() async {
    await #expect(processExitsWith: .success) {
        func width(minWidth: Double? = nil, maxWidth: Double? = nil, proposal: Double?) -> Double {
            let tree = LayoutTree(generation: 0)
            let child = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
            let frame = tree.newNativeFrame(child: child, minWidth: minWidth, maxWidth: maxWidth)
            return tree.computeNativeLayout(root: frame, proposal: ProposedSize(width: proposal, height: 100),
                                            in: LayoutRect(x: 0, y: 0, width: 100, height: 100)).size.width
        }
        let negative = width(minWidth: -10, proposal: 100)
        precondition(negative == 20, "minWidth −10 answered \(negative), SwiftUI 20")
        let negativeInfinite = width(minWidth: -.infinity, proposal: 100)
        precondition(negativeInfinite == 20, "minWidth −∞ answered \(negativeInfinite), SwiftUI 20")
        let infiniteOffered = width(maxWidth: .infinity, proposal: 100)
        precondition(infiniteOffered == 100, "maxWidth ∞ at 100 answered \(infiniteOffered), SwiftUI 100")
        let infiniteUnspecified = width(maxWidth: .infinity, proposal: nil)
        precondition(infiniteUnspecified == 20, "maxWidth ∞ at nil answered \(infiniteUnspecified), SwiftUI 20")
    }
}

// MARK: - Spacer minimum (P5)

/// SwiftUI answers `HStack(spacing: 0) { 20; Spacer(minLength: −30); 20 }` at
/// an unspecified proposal with 10 (P5). Green on arrival; red under "clamp
/// `minLength` at 0" (which reads 40).
@Test func aNegativeSpacerMinimumIsAccepted() async {
    await #expect(processExitsWith: .success) {
        let tree = LayoutTree(generation: 0)
        let a = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        let spacer = tree.newNativeSpacer(minLength: -30)
        let b = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }
        let stack = tree.newNativeLinearStack(children: [a, spacer, b], axis: .horizontal, spacing: 0)
        let width = tree.computeNativeLayout(root: stack, proposal: .unspecified,
                                             in: LayoutRect(x: 0, y: 0, width: 10, height: 20)).size.width
        precondition(width == 10, "Spacer(minLength: −30) between two 20s answered \(width), SwiftUI 10")
    }
}

// MARK: - Layout priority (P7, P7b)

/// SwiftUI orders +∞ like 1 and −∞ like −1 (P7, P7b): a horizontal stack
/// offered 100 holding two flexible leaves of ideal 80, the first under the
/// priority, allocates 80/20 for +∞ and 20/80 for −∞. By hand: +∞ sorts first
/// and takes its ideal 80, leaving 20 for the priority-0 leaf; with −∞ the
/// priority-0 leaf takes 80 first and the −∞ leaf gets the remaining 20.
///
/// **Red before**: the kernel trapped on ±∞ since `d250743`. Red after under
/// "map ±∞ to 0", which gives 50/50.
@Test func infiniteLayoutPrioritiesAreAcceptedAndOrderLikeFinitePriorities() async {
    await #expect(processExitsWith: .success) {
        func widths(firstPriority: Double) -> (Double, Double) {
            let tree = LayoutTree(generation: 0)
            let first = tree.newNativeLeaf { proposal in
                LayoutMeasurement(size: SizeD(width: Swift.min(80, proposal.width ?? 80), height: 10))
            }
            let second = tree.newNativeLeaf { proposal in
                LayoutMeasurement(size: SizeD(width: Swift.min(80, proposal.width ?? 80), height: 10))
            }
            let prioritized = tree.newNativeLayoutPriority(child: first, priority: firstPriority)
            let stack = tree.newNativeLinearStack(children: [prioritized, second], axis: .horizontal)
            tree.computeNativeLayout(root: stack, proposal: ProposedSize(width: 100, height: nil),
                                     in: LayoutRect(x: 0, y: 0, width: 100, height: 10))
            return (tree.layout(first).width, tree.layout(second).width)
        }
        let positive = widths(firstPriority: .infinity)
        precondition(positive == (80, 20), "priority +∞ allocated \(positive), SwiftUI 80/20")
        let negative = widths(firstPriority: -.infinity)
        precondition(negative == (20, 80), "priority −∞ allocated \(negative), SwiftUI 20/80")
    }
}

// MARK: - Aspect ratio (P8, P8b, P8c)

/// SwiftUI accepts a negative ratio (P8, P8b). With ratio −2 over a
/// proposal-echoing child — P8 measured `Color`, which takes the offer, and
/// since ruling CN-G the modifier answers its child, so the child is the
/// kernel's `Color` (a fixed child would answer its own 10×10, probe K4j;
/// plan task 6, lane 2):
/// - `.fit` at 100×80: `100 / −2 = −50 <= 80`, the width branch: 100×−50;
/// - `.fill` at 100×80: `−50 >= 80` is false, the height branch: −160×80;
/// - `.fit` at nil×80: 80 × −2 = −160, so −160×80;
/// - `.fit` at 100×nil: 100 / −2 = −50, so 100×−50.
///
/// **Red before**: the kernel trapped on a negative ratio. Red after under
/// "keep `width / height <= ratio`": its `.fit` 100×80 arm reads −160×80.
@Test func aNegativeAspectRatioIsAcceptedOnEveryProposedBranch() async {
    await #expect(processExitsWith: .success) {
        func size(_ mode: AspectRatioContentMode, _ width: Double?, _ height: Double?) -> SizeD {
            let tree = LayoutTree(generation: 0)
            let child = tree.newNativeLeaf { proposal in
                LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
            }
            let ratio = tree.newNativeAspectRatio(child: child, ratio: -2, contentMode: mode)
            return tree.computeNativeLayout(root: ratio, proposal: ProposedSize(width: width, height: height),
                                            in: LayoutRect(x: 0, y: 0, width: 100, height: 80)).size
        }
        let fit = size(.fit, 100, 80)
        precondition(fit == SizeD(width: 100, height: -50), "−2 .fit at 100×80 answered \(fit), SwiftUI 100×−50")
        let fill = size(.fill, 100, 80)
        precondition(fill == SizeD(width: -160, height: 80), "−2 .fill at 100×80 answered \(fill), SwiftUI −160×80")
        let heightOnly = size(.fit, nil, 80)
        precondition(heightOnly == SizeD(width: -160, height: 80),
                     "−2 .fit at nil×80 answered \(heightOnly), SwiftUI −160×80")
        let widthOnly = size(.fit, 100, nil)
        precondition(widthOnly == SizeD(width: 100, height: -50),
                     "−2 .fit at 100×nil answered \(widthOnly), SwiftUI 100×−50")
    }
}

/// The two-axis branch compares `width / ratio <= height` (`.fit`, `>=` for
/// `.fill`), which picks SwiftUI's branch in all 24 P8c arms where the old
/// `width / height <= ratio` picks it in 12 (ruling SA-K item 2). Four arms the
/// old predicate gets wrong, over a proposal-echoing child (P8c's `Color`;
/// since ruling CN-G the modifier answers its child, plan task 6 lane 2):
/// - 2 `.fit` at 100×−10: `50 <= −10` is false, height branch: −20×−10
///   (the old predicate answered 100×50);
/// - 2 `.fill` at 100×−10: `50 >= −10`, width branch: 100×50 (old −20×−10);
/// - −2 `.fit` at 100×0: `−50 <= 0`, width branch: 100×−50 (old: a trap on
///   the ratio);
/// - 2 `.fill` at −100×−80: `−50 >= −80`, width branch: −100×−50
///   (old −160×−80).
@Test func aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes() async {
    await #expect(processExitsWith: .success) {
        func size(_ ratio: Double, _ mode: AspectRatioContentMode, _ width: Double, _ height: Double) -> SizeD {
            let tree = LayoutTree(generation: 0)
            let child = tree.newNativeLeaf { proposal in
                LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
            }
            let node = tree.newNativeAspectRatio(child: child, ratio: ratio, contentMode: mode)
            return tree.computeNativeLayout(root: node, proposal: ProposedSize(width: width, height: height),
                                            in: LayoutRect(x: 0, y: 0, width: 100, height: 100)).size
        }
        let fitNegativeHeight = size(2, .fit, 100, -10)
        precondition(fitNegativeHeight == SizeD(width: -20, height: -10),
                     "2 .fit at 100×−10 answered \(fitNegativeHeight), SwiftUI −20×−10")
        let fillNegativeHeight = size(2, .fill, 100, -10)
        precondition(fillNegativeHeight == SizeD(width: 100, height: 50),
                     "2 .fill at 100×−10 answered \(fillNegativeHeight), SwiftUI 100×50")
        let fitZeroHeight = size(-2, .fit, 100, 0)
        precondition(fitZeroHeight == SizeD(width: 100, height: -50),
                     "−2 .fit at 100×0 answered \(fitZeroHeight), SwiftUI 100×−50")
        let fillBothNegative = size(2, .fill, -100, -80)
        precondition(fillBothNegative == SizeD(width: -100, height: -50),
                     "2 .fill at −100×−80 answered \(fillBothNegative), SwiftUI −100×−50")
    }
}

// MARK: - Computed values: the checkpoints' corollary (P6, N)

/// A measurement may be infinite; only a stored rect may not. A custom layout
/// asks a proposal-echoing leaf at ∞×∞ and gets ∞×∞ back (SwiftUI's `Color`
/// does the same, P6), then places it at a finite 10×10 proposal. Green on
/// arrival; red under "move checkpoint 3's non-finite test to checkpoint 2".
@Test func anInfiniteMeasurementIsAcceptedUntilItBecomesARect() async {
    await #expect(processExitsWith: .success) {
        struct AsksAtInfinity: ProposalLayout {
            func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
                let unbounded = subviews[0].sizeThatFits(.infinity)
                precondition(unbounded.size == SizeD(width: .infinity, height: .infinity),
                             "the echo leaf answered \(unbounded.size) at ∞")
                return LayoutMeasurement(size: SizeD(width: 10, height: 10))
            }
            func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
                subviews[0].place(at: Point(x: bounds.x, y: bounds.y),
                                  proposal: ProposedSize(width: 10, height: 10))
            }
        }
        let tree = LayoutTree(generation: 0)
        let echo = tree.newNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
        }
        let root = tree.newNativeLayout(AsksAtInfinity(), children: [echo])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 3, y: 4, width: 100, height: 100))
        let stored = tree.layout(echo)
        precondition(stored == LayoutRect(x: 3, y: 4, width: 10, height: 10), "the echo leaf stored \(stored)")
    }
}

/// SwiftUI's `Color` offered −10×−20 answers −10×−20 (P6): a negative proposal
/// is legal, and so is the negative rect it becomes. Green on arrival; red
/// under "reject negative proposal axes at checkpoint 1".
@Test func aNegativeProposalIsAccepted() async {
    await #expect(processExitsWith: .success) {
        let tree = LayoutTree(generation: 0)
        let echo = tree.newNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
        }
        let size = tree.computeNativeLayout(root: echo, proposal: ProposedSize(width: -10, height: -20),
                                            in: LayoutRect(x: 0, y: 0, width: -10, height: -20)).size
        precondition(size == SizeD(width: -10, height: -20), "offered −10×−20, answered \(size)")
    }
}
