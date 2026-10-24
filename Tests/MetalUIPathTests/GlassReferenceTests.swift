import Testing
import MetalUIPath

// Liquid Glass, lane A, reference tests 3-7 (rulings `LG-D`, `LG-G`, `LG-S`; spec
// `docs/superpowers/specs/2026-10-23-liquid-glass-design.md` §5). `GlassReference` is the
// CPU twin of the glass branch in `shaders.metal` and `replay.hlsl`: these pin its
// arithmetic on fields that vary on both axes, and the render tests
// (`GlassRenderTests`) pin the shader against it.

private typealias Ref = GlassReference

/// Two circles of diameter 60, surface gap `gap`, as one record: bounds the union,
/// two ellipse members, `blendK` = `k`.
private func twoCircles(gap: Float, k: Float) -> Ref.Record {
    let width = 120 + gap
    var record = Ref.Record(originX: 0, originY: 0, width: width, height: 60)
    record.flags = Ref.flags(lensRim: false, dark: false, memberCount: 2, ellipses: [true, true])
    record.blendK = k
    record.members = [
        Ref.Member(x: 0, y: 0, width: 60 / width, height: 1),
        Ref.Member(x: (60 + gap) / width, y: 0, width: 60 / width, height: 1),
    ]
    return record
}

/// **3** (`LG-G`). Two 60-point circles with surface gap `g` merge at the gap's centre iff
/// `spacing > 2g`: `smin = g/2 − k/4` there, zero at `k = 2g`. `g = 10`: 19 outside, 21 inside;
/// `g = 20`: 39 outside, 41 inside. Mutation: `h²k/4` → `h²k/2` in `smin` (the crossing moves
/// to `k = g`, and 19 and 39 read inside).
@Test(arguments: [(Float(10), Float(19), Float(21)), (Float(20), Float(39), Float(41))])
func theSmoothMinCrossesZeroAtSpacingTwiceTheGap(gap: Float, outside: Float, inside: Float) {
    let mid = 60 + gap / 2
    #expect(Ref.sdf(twoCircles(gap: gap, k: outside), mid, 30) > 0,
            "gap \(gap), k \(outside): the gap's centre is outside the blob")
    #expect(Ref.sdf(twoCircles(gap: gap, k: inside), mid, 30) < 0,
            "gap \(gap), k \(inside): the gap's centre is inside the blob")
    // The kernel itself: equal operands lose k/4, far operands lose nothing.
    #expect(abs(Ref.smin(5, 5, 20) - 0) < 1e-6)
    #expect(Ref.smin(5, 50, 20) == 5)
}

/// **4** (`LG-G`). A blob folds at most four members in tree order, and a container's members
/// chunk greedily by four, never across: five members are `0..<4` and `4..<5`; a record whose
/// flags claim seven members reads four. Mutation: chunk size 5 (`maxMembers` 5).
@Test func aBlobFoldsMembersInTreeOrderAndFourIsTheCap() {
    #expect(Ref.chunks(ofMemberCount: 5) == [0..<4, 4..<5])
    #expect(Ref.chunks(ofMemberCount: 8) == [0..<4, 4..<8])
    #expect(Ref.chunks(ofMemberCount: 3) == [0..<3])
    #expect(Ref.chunks(ofMemberCount: 0).isEmpty)
    #expect(Ref.maxMembers == 4)
    #expect(Ref.memberCount(Ref.flags(lensRim: false, dark: false, memberCount: 7)) == 4)
    #expect(Ref.memberCount(Ref.flags(lensRim: false, dark: false, memberCount: 1)) == 1)
    // Tree order: with three circles in a row, the fold's blob is a function of the order only
    // through `smin`'s non-associativity at the join — the middle one first reaches both.
    var row = Ref.Record(originX: 0, originY: 0, width: 200, height: 40)
    row.flags = Ref.flags(lensRim: false, dark: false, memberCount: 3, ellipses: [true, true, true])
    row.blendK = 24
    row.members = [Ref.Member(x: 0, y: 0, width: 0.2, height: 1),
                   Ref.Member(x: 0.4, y: 0, width: 0.2, height: 1),
                   Ref.Member(x: 0.8, y: 0, width: 0.2, height: 1)]
    let direct = Ref.smin(Ref.smin(Ref.ellipseSDF(100 - 20, 0, halfWidth: 20, halfHeight: 20),
                                   Ref.ellipseSDF(100 - 100, 0, halfWidth: 20, halfHeight: 20), 24),
                          Ref.ellipseSDF(100 - 180, 0, halfWidth: 20, halfHeight: 20), 24)
    #expect(abs(Ref.sdf(row, 100, 20) - direct) < 1e-4, "the fold is smin(smin(m0, m1), m2)")
}

private let blurredRead = SIMD4<Float>(0.30, 0.45, 0.20, 1)

/// A sharp field varying on both axes: premultiplied, opaque.
private func field(_ x: Float, _ y: Float) -> SIMD4<Float> {
    SIMD4(min(max(x / 100, 0), 1), min(max(y / 60, 0), 1), Float(Int(x / 4) + Int(y / 4)).truncatingRemainder(dividingBy: 2), 1)
}

private func lensRecord(flags: UInt32) -> Ref.Record {
    var record = Ref.Record(originX: 0, originY: 0, width: 100, height: 60)
    record.topLeft = 12; record.topRight = 12; record.bottomRight = 12; record.bottomLeft = 12
    record.flags = flags
    record.lensDepth = 6
    record.band = 12
    return record
}

/// **5** (`LG-D`). The lens reads the sharp target only inside the edge band: at `t = 1` (centre)
/// the result equals the lens-off result; one pixel inside the left edge it equals the blurred read
/// mixed toward the sharp read at `p − n·depth·(1−t)²` with weight `(1−t)²`; with the `lensRim`
/// bit clear nothing is read at all, and the dark bit does not switch the lens off.
/// Mutations: weight `(1−t)` for `(1−t)²`; lens off when the dark bit is set.
@Test func theLensReadsTheSharpTargetOnlyInsideTheEdgeBand() {
    let on = lensRecord(flags: Ref.flags(lensRim: true, dark: false, memberCount: 1))
    let off = lensRecord(flags: Ref.flags(lensRim: false, dark: false, memberCount: 1))
    let dark = lensRecord(flags: Ref.flags(lensRim: true, dark: true, memberCount: 1))
    func shade(_ r: Ref.Record, _ x: Float, _ y: Float) -> SIMD4<Float> {
        Ref.shade(r, x: x, y: y, blurred: blurredRead, sharp: { field($0, $1) })
    }
    // t = 1 at the centre: the band is 12 deep and the centre is 30 from the nearest edge.
    #expect(shade(on, 50, 30) == shade(off, 50, 30))
    #expect(shade(on, 50, 30) == blurredRead, "no tint, no rim: the blurred read itself")
    // One pixel inside the left edge, away from the corners: n = (-1, 0), t = 1/12.
    let (x, y): (Float, Float) = (1, 30)
    let t: Float = 1 / 12
    let weight = (1 - t) * (1 - t)
    let sharp = field(x + 6 * weight, y)
    let expected = blurredRead + (sharp - blurredRead) * weight
    let got = shade(off, x, y)
    #expect(got == blurredRead, "lensRim clear: the lens is off whatever the band says")
    var withLens = on
    withLens.rimStrength = 0
    let lensed = shade(withLens, x, y)
    for c in 0..<4 { #expect(abs(lensed[c] - expected[c]) < 1e-4, "channel \(c): \(lensed[c]) against \(expected[c])") }
    #expect(lensed != blurredRead, "the sharp read differs from the blurred one at the edge")
    withLens.flags = dark.flags
    #expect(shade(withLens, x, y) == lensed, "the dark bit changes no arithmetic")
}

/// **6** (`LG-D`, `LG-S`). The rim is brightest where the outward normal points to the upper left:
/// on a circle the upper-left edge reads `(0.65 + 0.35)` and the lower-right `(0.65 − 0.35)` of
/// the same strength, a ratio of 10/3; it decays with depth, and is exactly zero at `t ≥ 1` and
/// with the `lensRim` bit clear. Mutation: flip the light direction (`lightX`, `lightY` positive).
@Test func theRimIsBrightestTowardTheUpperLeft() {
    var circle = Ref.Record(originX: 0, originY: 0, width: 80, height: 80)
    circle.isEllipse = true
    circle.flags = Ref.flags(lensRim: true, dark: false, memberCount: 1)
    circle.band = 12
    circle.lensDepth = 0
    circle.rimStrength = 0.5
    let black = SIMD4<Float>(0, 0, 0, 1)
    func rim(_ r: Ref.Record, _ x: Float, _ y: Float) -> Float {
        Ref.shade(r, x: x, y: y, blurred: black, sharp: { _, _ in black })[0]
    }
    let k: Float = 0.70710678 * 39
    let upperLeft = rim(circle, 40 - k, 40 - k)
    let lowerRight = rim(circle, 40 + k, 40 + k)
    #expect(upperLeft > 0 && lowerRight > 0)
    #expect(abs(upperLeft / lowerRight - 10.0 / 3.0) < 0.1, "ratio \(upperLeft / lowerRight)")
    let deeper = 0.70710678 * 37
    #expect(rim(circle, 40 - deeper, 40 - deeper) < upperLeft, "the rim decays with depth")
    #expect(rim(circle, 40, 40) == 0, "the interior carries none")
    #expect(rim(circle, 40 - 0.70710678 * 27, 40 - 0.70710678 * 27) == 0, "none at t >= 1 (13 inside)")
    var off = circle
    off.flags = Ref.flags(lensRim: false, dark: false, memberCount: 1)
    #expect(rim(off, 40 - k, 40 - k) == 0, "lensRim clear: no rim")
}

/// **7a** (`LG-C`, reference side). The tint composites source-over the blurred read: a red tint of
/// alpha 0.3 over an opaque gray read is `0.3·red + 0.7·gray`, and swapping the order
/// (the tint under the base) would leave the opaque gray alone.
@Test func theReferenceCompositesATintSourceOverTheBase() {
    var record = Ref.Record(originX: 0, originY: 0, width: 40, height: 40)
    record.flags = Ref.flags(lensRim: false, dark: false, memberCount: 1)
    record.tint = SIMD4(1, 0, 0, 0.3)
    let gray = SIMD4<Float>(0.5, 0.5, 0.5, 1)
    let out = Ref.shade(record, x: 20, y: 20, blurred: gray, sharp: { _, _ in gray })
    #expect(abs(out[0] - (0.3 + 0.7 * 0.5)) < 1e-6 && abs(out[1] - 0.35) < 1e-6 && abs(out[2] - 0.35) < 1e-6 && out[3] == 1)
}
