import Foundation
import Testing
@testable import MetalUIPath

// Backdrop blur, lane 1, test 1.12 (rulings `BB-D` 4, `BB-K`; spec
// `docs/superpowers/specs/2026-10-10-backdrop-blur-design.md` §3.4, §5). The
// reference is what both renderers' shaders compute, on the CPU in `Float`, so
// a readback has a ground truth on every platform; these tests check the
// reference against mathematics independent of both: an `erf` step.

/// The error function (Abramowitz and Stegun 7.1.26, |error| < 1.5e-7), the
/// independent truth the Gaussian's step response is checked against.
private func erf(_ x: Double) -> Double {
    if abs(x) > 6 { return x < 0 ? -1 : 1 }
    let t = 1 / (1 + 0.3275911 * abs(x))
    let poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
    let y = 1 - poly * exp(-x * x)
    return x < 0 ? -y : y
}

/// A 1536 x 4 premultiplied strip: black (0) left of x = 768 + `phase`, white
/// (1) right -- wide enough that the clamped edges are 6 sigma from the step
/// at sigma 104 (`BB-R`).
private let stripWidth = 1536
private func step(phase: Int) -> [Float] {
    var pixels = [Float](repeating: 0, count: stripWidth * 4 * 4)
    for y in 0..<4 { for x in (stripWidth / 2 + phase)..<stripWidth { for c in 0..<4 { pixels[(y * stripWidth + x) * 4 + c] = 1 } } }
    return pixels
}

/// **1.12a** (`BB-D` 4). The reference blur of a step is an `erf` step within
/// two levels (of 255) for the three sigmas the design names, in device
/// pixels: 16 (two levels of downsampling), 52 (four) and 104 (five, 52 points
/// at scale 2). Mutation: drop the weight normalization in `gaussianWeights`.
@Test func theReferenceBlurMatchesAnErfStepWithinTwoLevels() throws {
    for sigma in [Float(16), 52, 104] {
        var worst = 0.0
        // Phases that are not multiples of 2^L, so the downsample's blocks do
        // not align with the step.
        for phase in [0, 1, 7, 13] {
            let blurred = BackdropBlurReference.blur(step(phase: phase), width: stripWidth, height: 4, sigma: sigma)
            try #require(blurred.count == stripWidth * 4 * 4)
            for x in 0..<stripWidth {
                let want = 0.5 * (1 + erf((Double(x) + 0.5 - Double(stripWidth / 2 + phase)) / (Double(sigma) * 2.0.squareRoot())))
                let got = Double(blurred[(2 * stripWidth + x) * 4 + 1])
                worst = max(worst, abs(got - want) * 255)
            }
        }
        print("BB-D reference sigma \(sigma): worst \(worst) levels from the erf step")
        #expect(worst <= 2, "sigma \(sigma): \(worst) levels from the erf step")
    }
}

/// **1.12b** (`BB-D` 2). The level count follows sigma: the smallest L with
/// `sigma / 2^L <= 4`, at most six. Literal levels for six sigmas. Mutation:
/// the threshold 4 -> 8 (52 reads 3, not 4).
@Test func theLevelCountFollowsSigma() {
    #expect(BackdropBlurReference.levels(sigma: 0) == 0)
    #expect(BackdropBlurReference.levels(sigma: 4) == 0)
    #expect(BackdropBlurReference.levels(sigma: 5) == 1)
    #expect(BackdropBlurReference.levels(sigma: 16) == 2)
    #expect(BackdropBlurReference.levels(sigma: 52) == 4)
    #expect(BackdropBlurReference.levels(sigma: 104) == 5)
    #expect(BackdropBlurReference.levels(sigma: 100_000) == 6, "capped at MUIBackdropBlurMaxLevel")
}

/// **1.12c** (`BB-D` 2). The kernel sums to one and the in-file `exp` matches
/// known values (no libm). Mutation: `expNonPositive` returns 1.
@Test func theKernelIsNormalizedAndTheExponentialMatches() {
    for sigma in [Float(0.5), 2, 4, 13] {
        let w = BackdropBlurReference.gaussianWeights(sigma: sigma)
        let total = w[0] + 2 * w.dropFirst().reduce(0, +)
        #expect(abs(total - 1) < 1e-5, "sigma \(sigma): sum \(total)")
        #expect(w.count == Int((3 * sigma).rounded(.up)) + 1, "taps +-ceil(3 sigma)")
    }
    #expect(abs(BackdropBlurReference.expNonPositive(-1) - 0.36787944) < 1e-6)
    #expect(abs(BackdropBlurReference.expNonPositive(-10) - 4.539993e-5) < 1e-9)
    #expect(BackdropBlurReference.expNonPositive(0) == 1)
}

/// **1.12d.** A uniform backdrop stays uniform under the whole chain, at every
/// level count (the clamped edges and the odd-size downsample repeat the last
/// texel, so nothing darkens at an edge). Mutation: zero-fill the edges.
@Test func aUniformBackdropStaysUniform() {
    for (w, h, sigma) in [(37, 23, Float(52)), (64, 64, 16), (5, 3, 104)] {
        let pixels = [Float](repeating: 0.6, count: w * h * 4)
        let blurred = BackdropBlurReference.blur(pixels, width: w, height: h, sigma: sigma)
        let worst = blurred.map { abs($0 - 0.6) }.max() ?? 1
        #expect(worst < 1e-4, "\(w)x\(h) sigma \(sigma): off by \(worst)")
    }
}
