import Testing
import MetalUICore
@testable import MetalUILayout

// Plan task 11, part 2, lane 3: the kernel's `aspectRatio` with no ratio
// (ruling `TE-AM`; spec
// `docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md` §8 lane 3,
// test 3.4). Portable — this file runs on Linux and Windows CI with the rest of
// `MetalUILayoutTests`. Every row is a probe reading
// (`docs/probes/swiftui-shapes-and-rendering.swift`, arms A1–A3): a `Color` is
// a leaf answering its proposal with a nil axis 10, and A3's `Color` with
// `.frame(idealWidth: 40, idealHeight: 20)` a leaf answering its proposal with
// a nil axis 40 or 20.

private func leaf(_ tree: LayoutTree, idealWidth: Double, idealHeight: Double) -> LayoutNodeID {
    tree.newNativeLeaf { proposal in
        LayoutMeasurement(size: SizeD(width: proposal.width ?? idealWidth,
                                      height: proposal.height ?? idealHeight))
    }
}

private func size(_ w: Double, _ h: Double) -> SizeD { SizeD(width: w, height: h) }

private let inf = Double.infinity

/// The probe's five proposals, in its order.
private let proposals = [ProposedSize(width: nil, height: nil), ProposedSize(width: 100, height: 60),
                         ProposedSize(width: 0, height: 0), ProposedSize(width: inf, height: inf),
                         ProposedSize(width: 100, height: nil)]

private func answers(idealWidth: Double, idealHeight: Double,
                     contentMode: AspectRatioContentMode) -> [SizeD] {
    proposals.map { proposal in
        let tree = LayoutTree(generation: 0)
        let root = tree.newNativeAspectRatio(child: leaf(tree, idealWidth: idealWidth,
                                                         idealHeight: idealHeight),
                                             ratio: nil, contentMode: contentMode)
        return tree.measureNativeLayout(root: root, proposal: proposal).size
    }
}

/// **3.4 — `aspectRatio(nil)` takes the child's ideal ratio, its answer at
/// nil×nil** (`TE-AM`). A3: an ideal 40×20 child (ratio 2) fits 100×60 as
/// 100×50 and answers 40×20 at nil×nil; A1/A2: a `Color`-like child (ideal
/// 10×10, ratio 1) fits 100×60 as 60×60 and fills it as 100×100. The rows are
/// the probe's verbatim, all five proposals each. Then two branches the probe
/// has no arm for, derived before the run from `TE-AM`'s rule: an ideal with a
/// zero width (ratio 0) and one with an infinite width (ratio ∞) pass the
/// proposal through — 100×60 answers 100×60 — rather than dividing by it; and
/// the placed child of A3's fit row sits at the node's origin, 100×50.
///
/// Mutation: **M3d** a nil ratio treated as 1 (A3 reads 60×60, the zero-ratio
/// arm 60×60).
@Test func aspectRatioWithNoRatioTakesTheChildsIdealRatio() throws {
    #expect(answers(idealWidth: 40, idealHeight: 20, contentMode: .fit)
                == [size(40, 20), size(100, 50), size(0, 0), size(inf, inf), size(100, 50)], "A3")
    #expect(answers(idealWidth: 10, idealHeight: 10, contentMode: .fit)
                == [size(10, 10), size(60, 60), size(0, 0), size(inf, inf), size(100, 100)], "A1")
    #expect(answers(idealWidth: 10, idealHeight: 10, contentMode: .fill)
                == [size(10, 10), size(100, 100), size(0, 0), size(inf, inf), size(100, 100)], "A2")

    let zero = answers(idealWidth: 0, idealHeight: 20, contentMode: .fit)
    #expect(zero[1] == size(100, 60), "a zero ideal ratio passes 100×60 through: \(zero[1])")
    let infinite = answers(idealWidth: inf, idealHeight: 20, contentMode: .fit)
    #expect(infinite[1] == size(100, 60), "an infinite ideal ratio passes 100×60 through: \(infinite[1])")

    let tree = LayoutTree(generation: 0)
    let child = leaf(tree, idealWidth: 40, idealHeight: 20)
    let root = tree.newNativeAspectRatio(child: child, ratio: nil, contentMode: .fit)
    tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 60),
                             in: LayoutRect(x: 0, y: 0, width: 100, height: 60))
    #expect(tree.layout(child).width == 100 && tree.layout(child).height == 50,
            "A3 placed: \(tree.layout(child))")
}
