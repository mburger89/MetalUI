import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIText
@testable import MetalUI

// Element-level tests of plan task 6 ("containers"),
// `docs/superpowers/specs/2026-09-16-containers-design.md`; rulings `CN-` in
// `docs/superpowers/2026-09-16-containers-decisions.md`. Arm names are
// `docs/probes/swiftui-stack-algorithms.swift`'s (revision 4), whose header
// holds the recorded output. Kernel-level pins of the same rulings are in
// `Tests/MetalUILayoutTests/NativeStackDistributionTests.swift`.

@MainActor
private final class BoundsLog {
    var bounds: [String: Bounds<Pixels>] = [:]
}

/// The probe's `Leaf` as an element: `clamp(proposal ?? ideal, min, max)` per
/// axis, recording its prepaint bounds under `name`.
private struct ClampProbe: ProposalElement {
    let name: String
    var minW: Double, idealW: Double, maxW: Double
    var minH: Double, idealH: Double, maxH: Double
    let log: BoundsLog

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let (minW, idealW, maxW, minH, idealH, maxH) = (self.minW, self.idealW, self.maxW, self.minH, self.idealH, self.maxH)
        let node = pass.requestNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(
                width: Swift.min(Swift.max(proposal.width ?? idealW, minW), maxW),
                height: Swift.min(Swift.max(proposal.height ?? idealH, minH), maxH)))
        }
        return (node, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        log.bounds[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

private func flexW(_ name: String, _ min: Double, _ ideal: Double, _ max: Double, _ log: BoundsLog) -> ClampProbe {
    ClampProbe(name: name, minW: min, idealW: ideal, maxW: max, minH: 20, idealH: 20, maxH: 20, log: log)
}

private func flexH(_ name: String, _ min: Double, _ ideal: Double, _ max: Double, _ log: BoundsLog) -> ClampProbe {
    ClampProbe(name: name, minW: 20, idealW: 20, maxW: 20, minH: min, idealH: ideal, maxH: max, log: log)
}

private func fixed(_ name: String, _ width: Double, _ height: Double, _ log: BoundsLog) -> ClampProbe {
    ClampProbe(name: name, minW: width, idealW: width, maxW: width, minH: height, idealH: height, maxH: height,
               log: log)
}

private func rect(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(width), height: Pixels(height)))
}

/// `HStack` and `VStack` distribute as the probe reads, through the element API
/// (CN-B). Each stack is a window root offered the window's size and, until
/// lane 4's `CN-J`, stored at the full window, so the cross axis centres a
/// 20pt child in 50 at 15.
///
/// - G1 `HStack(0){a 20..100; b 60..100}` at 100×50: a 40, b 60 at x 40.
/// - G2 `HStack(0){a 0..80 prio 1; b 30..80}`: a 70, b 30 at x 70.
/// - G6 `HStack(0){a fixed 80; Spacer(minLength: 8); b 0..80}`: b 12 at x 88.
/// - G15 `VStack(0){a 0..80; b 20..80}` at 50×100 (heights): 50 / 50.
///
/// Mutation: swap `HStack`'s axis in `NativeElements.swift` (measured at
/// `9e439cb`, it reddens eleven other tests; the spec lists them).
@MainActor
@Test func hStackAndVStackDistributeAsTheProbeReadsThroughTheElementAPI() {
    do { // G1
        let log = BoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 1)
        var root = HStack(spacing: Pixels(0)) {
            flexW("a", 20, 100, 100, log)
            flexW("b", 60, 100, 100, log)
        }
        frame.render(&root)
        #expect(log.bounds["a"] == rect(0, 15, 40, 20), "G1 a")
        #expect(log.bounds["b"] == rect(40, 15, 60, 20), "G1 b")
    }
    do { // G2
        let log = BoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 1)
        var root = HStack(spacing: Pixels(0)) {
            flexW("a", 0, 80, 80, log).layoutPriority(1)
            flexW("b", 30, 80, 80, log)
        }
        frame.render(&root)
        #expect(log.bounds["a"] == rect(0, 15, 70, 20), "G2 a")
        #expect(log.bounds["b"] == rect(70, 15, 30, 20), "G2 b")
    }
    do { // G6
        let log = BoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 1)
        var root = HStack(spacing: Pixels(0)) {
            fixed("a", 80, 20, log)
            Spacer(minLength: Pixels(8))
            flexW("b", 0, 80, 80, log)
        }
        frame.render(&root)
        #expect(log.bounds["a"] == rect(0, 15, 80, 20), "G6 a")
        #expect(log.bounds["b"] == rect(88, 15, 12, 20), "G6 b")
    }
    do { // G15
        let log = BoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(50), height: Pixels(100)), scaleFactor: 1)
        var root = VStack(spacing: Pixels(0)) {
            flexH("a", 0, 80, 80, log)
            flexH("b", 20, 80, 80, log)
        }
        frame.render(&root)
        #expect(log.bounds["a"] == rect(15, 0, 20, 50), "G15 a")
        #expect(log.bounds["b"] == rect(15, 50, 20, 50), "G15 b")
    }
}

/// A `ProposalText` in a stack is shaped once per distinct width (CN-B's
/// shaping cost; counted, never timed).
///
/// Three distinct strings in `HStack(spacing: 0)`, a fresh `ShapingCache`, one
/// cold frame. Derived by hand before the run: the three texts form one
/// priority group of three, so each is probed at main ∞ (shaped at ∞) and at
/// main 0 (shaped at `smallestWrapWidth`, 0.5), then offered its share of the
/// 600pt root (a finite width, each at least 600 − 2 × 600 / 3 = 200 wide
/// minus what the others answered, far wider than any of the three strings),
/// and it answers its one-line width. Paint shapes at `measuredWidth`, the
/// placed pre-rounding width, which is that answer and differs from ∞, 0.5 and
/// the offer. So 3 × 4 = **12 misses**.
/// - At the finite root the placement solve repeats measurement's proposals,
///   all kernel-cache hits, so no text measures again: **12 lookups**.
/// - Inside a vertical `ProposalScrollView` the stack is measured at
///   (600, nil) and placed after a second pass at its own height (CN-E): the
///   same three widths per text again, now shaping-cache hits: 9 + 9 + 3 paint
///   = **21 lookups**, still **12 misses**.
///
/// Before the lane each text is shaped at nil and at its placed width: 6
/// misses. Mutations: shape without the cache (the scroll arm's misses read
/// 21); key the shaping cache on width rounded to an integer.
@MainActor
@Test func aProposalTextInAStackIsShapedOncePerDistinctWidth() {
    do {
        let cache = ShapingCache()
        let frame = Frame(contentSize: Size(width: Pixels(600), height: Pixels(200)), scaleFactor: 1,
                          shapingCache: cache)
        var root = HStack(spacing: Pixels(0)) {
            ProposalText("Alpha")
            ProposalText("Bravo two")
            ProposalText("Charlie three words")
        }
        frame.render(&root)
        #expect(cache.misses == 12, "finite root: misses")
        #expect(cache.lookups == 12, "finite root: lookups")
    }
    do {
        let cache = ShapingCache()
        let frame = Frame(contentSize: Size(width: Pixels(600), height: Pixels(200)), scaleFactor: 1,
                          shapingCache: cache)
        var root = ProposalScrollView(.vertical) {
            HStack(spacing: Pixels(0)) {
                ProposalText("Alpha")
                ProposalText("Bravo two")
                ProposalText("Charlie three words")
            }
        }
        frame.render(&root)
        #expect(cache.misses == 12, "scroll viewport: misses")
        #expect(cache.lookups == 21, "scroll viewport: lookups")
    }
}
