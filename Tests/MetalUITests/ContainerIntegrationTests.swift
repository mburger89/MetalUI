import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
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
/// (CN-B). Each stack is a window root offered the window's size; each answers
/// the window's main-axis size and 20 across, and since lane 4's `CN-J` is
/// centred at that answer, so a 20pt child sits 15 in on the 50pt cross axis
/// (before CN-J the root filled the window and the stack's cross alignment
/// centred the child at the same 15).
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

/// Lane 2 through the element API (CN-C, CN-F).
///
/// - SP1 `HStack(spacing: 0){a20; Spacer(); b20}` under `.fixedSize()` (so
///   the stack is proposed nil×nil, as the probe's arm is): b 28 after a, the
///   default minimum 8. Since lane 4's CN-J the 48×20 root is centred in the
///   100×50 window, at (26, 15), so a reads x 26 and b x 54.
/// - G4 `HStack(spacing: 0){a fixed 20; b fixed 20 .frame(maxWidth:
///   .infinity)}`, a 200×50 window root: b centred in 180 at x 100 (y 15: the
///   200×20 root is centred in the 50pt window, CN-J). Revision 5's G4r,
///   the frame declared first: b at 80, a at 180.
///
/// Before the lane SP1's b reads 20 (a nil minimum was 0) and G4r's frame is
/// served first at 100 (b at 40, a at 100). Mutation: nil → 0 in
/// `newNativeSpacer`.
@MainActor
@Test func aDefaultSpacerAndAGreedyFrameThroughTheElementAPI() {
    do { // SP1
        let log = BoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(50)), scaleFactor: 1)
        var root = HStack(spacing: Pixels(0)) {
            fixed("a", 20, 20, log)
            Spacer()
            fixed("b", 20, 20, log)
        }.fixedSize()
        frame.render(&root)
        #expect(log.bounds["a"] == rect(26, 15, 20, 20), "SP1 a")
        #expect(log.bounds["b"] == rect(54, 15, 20, 20), "SP1 b")
    }
    do { // G4
        let log = BoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(50)), scaleFactor: 1)
        var root = HStack(spacing: Pixels(0)) {
            fixed("a", 20, 20, log)
            fixed("b", 20, 20, log).frame(maxWidth: Pixels(.infinity))
        }
        frame.render(&root)
        #expect(log.bounds["a"] == rect(0, 15, 20, 20), "G4 a")
        #expect(log.bounds["b"] == rect(100, 15, 20, 20), "G4 b")
    }
    do { // G4r
        let log = BoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(50)), scaleFactor: 1)
        var root = HStack(spacing: Pixels(0)) {
            fixed("b", 20, 20, log).frame(maxWidth: Pixels(.infinity))
            fixed("a", 20, 20, log)
        }
        frame.render(&root)
        #expect(log.bounds["b"] == rect(80, 15, 20, 20), "G4r b")
        #expect(log.bounds["a"] == rect(180, 15, 20, 20), "G4r a")
    }
}

// MARK: - Lane 3: platform-default spacing and typed stack alignments (CN-H, CN-I)

/// A fixed 20×20 native leaf, for the kernel halves below (plain `import
/// MetalUILayout`: the public registrars only).
private func kernelLeaf(_ tree: LayoutTree, _ width: Double = 20, _ height: Double = 20) -> LayoutNodeID {
    tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: width, height: height)) }
}

/// Lays `root` out at nil×nil in bounds of its own answer at the origin (the
/// probe's `Probe` layout) and returns that answer.
private func kernelRun(_ tree: LayoutTree, _ root: LayoutNodeID) -> SizeD {
    let unspecified = ProposedSize(width: nil, height: nil)
    let answer = tree.computeNativeLayout(root: root, proposal: unspecified,
                                          in: LayoutRect(x: 0, y: 0, width: 0, height: 0)).size
    tree.computeNativeLayout(root: root, proposal: unspecified,
                             in: LayoutRect(x: 0, y: 0, width: answer.width, height: answer.height))
    return answer
}

/// CN-H: with no `spacing:`, a stack puts 8 between two views and nothing
/// beside a spacer; an empty conditional adds nothing. Every arm at nil×nil
/// (the element half roots each stack under `.fixedSize()`, so the stack is
/// proposed nil×nil as the probe's arm is). Since lane 4 (CN-J) each element
/// root is centred at its answer in the 100×100 window, so the element half's
/// rects carry that offset: a 48×20 root sits at (26, 40), so b at 28 reads
/// x 54; a 40×20 root at (30, 40); a 20×48 root at (40, 26); a 20×40 at
/// (40, 30).
///
/// - S rect|rect: `HStack{a20; b20}` b at x 28; `VStack{a20; b20}` b at y 28.
/// - SP2 `HStack{a20; Spacer(); b20}`: 48×20, b at 28 (the spacer's own 8,
///   no spacing beside it).
/// - SP3 `HStack{a20; Spacer(minLength: 0); b20}`: 40×20, b at 20.
/// - SP7 `VStack{a20; Spacer(minLength: 0); b20}`: 20×40, b at y 20.
/// - G23 `HStack{a20; if false {…}; b20}`: 48×20, b at 28 (element half only;
///   the kernel never sees the conditional).
/// - SC5 (probe revision 7) `ProposalScrollView(.vertical){a20;
///   Spacer(minLength: 0); b20}`: b 20 below a, against SC5c's 28 without the
///   spacer — the several-children lowering is a default-spacing stack.
///   Added after the lane: the mutation "lower with an explicit 8" left the
///   suite green (b reads 28 under it).
///
/// Before the lane `HStack`'s default is an explicit 8, applied beside a spacer
/// too: SP3 reads 56 and SP2 64. Mutations: apply 8 beside spacers (SP2, SP3,
/// SP7 move); default nil → 0 (S rect|rect and G23 move); lower
/// `ProposalScrollView`'s children with an explicit 8 (SC5 moves).
@MainActor
@Test func aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer() {
    // Kernel half.
    do { // S rect|rect, horizontal and vertical
        let tree = LayoutTree(generation: 0)
        let b = kernelLeaf(tree)
        let root = tree.newNativeLinearStack(children: [kernelLeaf(tree), b], axis: .horizontal, spacing: nil)
        #expect(kernelRun(tree, root) == SizeD(width: 48, height: 20), "kernel S rect|rect hstack size")
        #expect(tree.layout(b) == LayoutRect(x: 28, y: 0, width: 20, height: 20), "kernel S rect|rect hstack b")
    }
    do {
        let tree = LayoutTree(generation: 0)
        let b = kernelLeaf(tree)
        let root = tree.newNativeLinearStack(children: [kernelLeaf(tree), b], axis: .vertical, spacing: nil)
        #expect(kernelRun(tree, root) == SizeD(width: 20, height: 48), "kernel S rect|rect vstack size")
        #expect(tree.layout(b) == LayoutRect(x: 0, y: 28, width: 20, height: 20), "kernel S rect|rect vstack b")
    }
    do { // SP2
        let tree = LayoutTree(generation: 0)
        let b = kernelLeaf(tree)
        let root = tree.newNativeLinearStack(children: [kernelLeaf(tree), tree.newNativeSpacer(), b],
                                             axis: .horizontal, spacing: nil)
        #expect(kernelRun(tree, root) == SizeD(width: 48, height: 20), "kernel SP2 size")
        #expect(tree.layout(b) == LayoutRect(x: 28, y: 0, width: 20, height: 20), "kernel SP2 b")
    }
    do { // SP3
        let tree = LayoutTree(generation: 0)
        let b = kernelLeaf(tree)
        let root = tree.newNativeLinearStack(children: [kernelLeaf(tree), tree.newNativeSpacer(minLength: 0), b],
                                             axis: .horizontal, spacing: nil)
        #expect(kernelRun(tree, root) == SizeD(width: 40, height: 20), "kernel SP3 size")
        #expect(tree.layout(b) == LayoutRect(x: 20, y: 0, width: 20, height: 20), "kernel SP3 b")
    }
    do { // SP7
        let tree = LayoutTree(generation: 0)
        let b = kernelLeaf(tree)
        let root = tree.newNativeLinearStack(children: [kernelLeaf(tree), tree.newNativeSpacer(minLength: 0), b],
                                             axis: .vertical, spacing: nil)
        #expect(kernelRun(tree, root) == SizeD(width: 20, height: 40), "kernel SP7 size")
        #expect(tree.layout(b) == LayoutRect(x: 0, y: 20, width: 20, height: 20), "kernel SP7 b")
    }

    // Element half.
    func render<Root: Element>(_ root: Root) {
        var root = root
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1)
        frame.render(&root)
    }
    do { // S rect|rect
        let log = BoundsLog()
        render(HStack { fixed("a", 20, 20, log); fixed("b", 20, 20, log) }.fixedSize())
        #expect(log.bounds["b"] == rect(54, 40, 20, 20), "element S rect|rect hstack b")
        render(VStack { fixed("c", 20, 20, log); fixed("d", 20, 20, log) }.fixedSize())
        #expect(log.bounds["d"] == rect(40, 54, 20, 20), "element S rect|rect vstack b")
    }
    do { // SP2
        let log = BoundsLog()
        render(HStack { fixed("a", 20, 20, log); Spacer(); fixed("b", 20, 20, log) }.fixedSize())
        #expect(log.bounds["b"] == rect(54, 40, 20, 20), "element SP2 b")
    }
    do { // SP3
        let log = BoundsLog()
        render(HStack { fixed("a", 20, 20, log); Spacer(minLength: Pixels(0)); fixed("b", 20, 20, log) }.fixedSize())
        #expect(log.bounds["b"] == rect(50, 40, 20, 20), "element SP3 b")
    }
    do { // SP7
        let log = BoundsLog()
        render(VStack { fixed("a", 20, 20, log); Spacer(minLength: Pixels(0)); fixed("b", 20, 20, log) }.fixedSize())
        #expect(log.bounds["b"] == rect(40, 50, 20, 20), "element SP7 b")
    }
    do { // G23
        let log = BoundsLog()
        let showsMiddle = log.bounds.count > 0
        render(HStack {
            fixed("a", 20, 20, log)
            if showsMiddle { fixed("m", 20, 20, log) }
            fixed("b", 20, 20, log)
        }.fixedSize())
        #expect(log.bounds["m"] == nil, "G23 the conditional is empty")
        #expect(log.bounds["b"] == rect(54, 40, 20, 20), "element G23 b")
    }
    do { // SC5 (probe revision 7): a vertical ProposalScrollView's direct children
        let log = BoundsLog()
        render(ProposalScrollView(.vertical) {
            fixed("a", 20, 20, log); Spacer(minLength: Pixels(0)); fixed("b", 20, 20, log)
        })
        render(ProposalScrollView(.vertical) { fixed("ca", 20, 20, log); fixed("cb", 20, 20, log) })
        let (a, b) = (log.bounds["a"]?.origin.y.value, log.bounds["b"]?.origin.y.value)
        let (ca, cb) = (log.bounds["ca"]?.origin.y.value, log.bounds["cb"]?.origin.y.value)
        #expect(cb.flatMap { cb in ca.map { cb - $0 } } == 28, "SC5c control: 8 between two views")
        #expect(b.flatMap { b in a.map { b - $0 } } == 20, "SC5: none beside the spacer")
    }
}

/// CN-H: an explicit spacing is used verbatim for every gap, beside a spacer
/// included.
///
/// - S control: `HStack(spacing: 0){a20; b20}` b at 20; `HStack(spacing:
///   20)` b at 40; `VStack(spacing: 20)` b at y 40.
/// - SP4 `HStack(spacing: 20){a20; Spacer(minLength: 0); b20}`: 80×20, b at
///   60.
///
/// Each root sits centred at its answer in the 100×100 window since lane 4
/// (CN-J): SP4's 80×20 at (10, 40), so b at 60 reads x 70; `HStack(spacing: 0)`
/// 40×20 at (30, 40), b 50; `HStack(spacing: 20)` 60×20 at (20, 40), b 60;
/// `VStack(spacing: 20)` 20×60 at (40, 20), b y 60.
///
/// Green on arrival (an explicit 20 was already applied everywhere), so the
/// test first requires SP3's default (b at 20, test 3.1's arm) and SP4 to
/// disagree. Mutation: treat an explicit spacing as default beside a spacer
/// (SP4 reads b at 20).
@MainActor
@Test func explicitStackSpacingIsUsedForEveryGapIncludingBesideASpacer() throws {
    func render<Root: Element>(_ root: Root) {
        var root = root
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1)
        frame.render(&root)
    }
    let log = BoundsLog()
    render(HStack { fixed("a3", 20, 20, log); Spacer(minLength: Pixels(0)); fixed("b3", 20, 20, log) }.fixedSize())
    render(HStack(spacing: Pixels(20)) {
        fixed("a4", 20, 20, log); Spacer(minLength: Pixels(0)); fixed("b4", 20, 20, log)
    }.fixedSize())
    try #require(log.bounds["b3"] != nil && log.bounds["b4"] != nil)
    try #require(log.bounds["b3"]!.origin.x != log.bounds["b4"]!.origin.x,
                 "SP3 (default) and SP4 (explicit 20) must disagree before SP4 can say anything")
    #expect(log.bounds["b4"] == rect(70, 40, 20, 20), "SP4 b")

    render(HStack(spacing: Pixels(0)) { fixed("a", 20, 20, log); fixed("b0", 20, 20, log) }.fixedSize())
    #expect(log.bounds["b0"] == rect(50, 40, 20, 20), "S control hstack(0) b")
    render(HStack(spacing: Pixels(20)) { fixed("a", 20, 20, log); fixed("b20", 20, 20, log) }.fixedSize())
    #expect(log.bounds["b20"] == rect(60, 40, 20, 20), "S control hstack(20) b")
    render(VStack(spacing: Pixels(20)) { fixed("a", 20, 20, log); fixed("v20", 20, 20, log) }.fixedSize())
    #expect(log.bounds["v20"] == rect(40, 60, 20, 20), "S control vstack(20) b")
}

/// CN-I: `HStack(alignment:spacing:)` takes a `VerticalAlignment` and
/// `VStack(alignment:spacing:)` a `HorizontalAlignment`, in SwiftUI's argument
/// order, and each places its children at the probe's positions.
///
/// - A1 `HStack(alignment: .top / .center / .bottom, spacing: 0){a 20×10; b
///   20×30}`: 40×30, a at y 0 / 10 / 20.
/// - A2 `VStack(alignment: .leading / .center / .trailing, spacing: 0){a
///   10×20; b 30×20}`: 30×40, a at x 0 / 10 / 20.
///
/// Each root is `.fixedSize()` (proposed nil×nil, as the probe's arms are) in
/// a window of exactly the stack's answer. Before the lane it does not compile.
/// Mutation: map `.top` to `.center` in `VerticalAlignment`'s mapping.
@MainActor
@Test func hStackAndVStackPlaceChildrenAtTheirTypedAlignments() {
    let vertical: [(VerticalAlignment, Float)] = [(.top, 0), (.center, 10), (.bottom, 20)]
    for (alignment, y) in vertical {
        let log = BoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(40), height: Pixels(30)), scaleFactor: 1)
        var root = HStack(alignment: alignment, spacing: Pixels(0)) {
            fixed("a", 20, 10, log)
            fixed("b", 20, 30, log)
        }.fixedSize()
        frame.render(&root)
        #expect(log.bounds["a"] == rect(0, y, 20, 10), "A1 \(alignment) a")
        #expect(log.bounds["b"] == rect(20, 0, 20, 30), "A1 \(alignment) b")
    }
    let horizontal: [(HorizontalAlignment, Float)] = [(.leading, 0), (.center, 10), (.trailing, 20)]
    for (alignment, x) in horizontal {
        let log = BoundsLog()
        let frame = Frame(contentSize: Size(width: Pixels(30), height: Pixels(40)), scaleFactor: 1)
        var root = VStack(alignment: alignment, spacing: Pixels(0)) {
            fixed("a", 10, 20, log)
            fixed("b", 30, 20, log)
        }.fixedSize()
        frame.render(&root)
        #expect(log.bounds["a"] == rect(x, 0, 10, 20), "A2 \(alignment) a")
        #expect(log.bounds["b"] == rect(0, 20, 30, 20), "A2 \(alignment) b")
    }
}

/// CN-H's one declared non-adoption, pinned as MetalUI's rule: a vertical stack
/// of `ProposalText`s gets 8 at a text edge. SwiftUI's is font-derived — probe
/// S reads `VStack` text|text **0**, rect|text **4.74**, text|rect **8.15**
/// (and 8 horizontally for every pair) — and the kernel has no font metrics or
/// spacing-preference channel to derive it from (owner task 11, with baseline
/// alignment).
///
/// Three `VStack(alignment: .leading)` roots under `.fixedSize()` (each inside a
/// 300×300 top-leading frame, so the stack's top is the window's whatever its
/// height; since lane 4's CN-J a bare root would be centred at its answer), the marker
/// `m` a fixed 20×20 leaf: `{text; text; m}` at spacing 0 puts m at 2h (the
/// control, from which h, one line's height, is read); `{text; m}` at default
/// spacing puts m at h + 8 (text|rect); `{text; text; m}` at default spacing at
/// 2h + 16 (text|text is the difference, 8).
///
/// Green on arrival (the old default was an explicit 8); requires the control
/// to differ. Mutation: default nil → 0 (both gaps read 0).
@MainActor
@Test func aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing() throws {
    func markerY<Root: Element>(_ root: Root, _ log: BoundsLog) throws -> Float {
        var root = root
        let frame = Frame(contentSize: Size(width: Pixels(300), height: Pixels(300)), scaleFactor: 1)
        frame.render(&root)
        return try #require(log.bounds["m"]).origin.y.value
    }
    let log = BoundsLog()
    let control = try markerY(VStack(alignment: .leading, spacing: Pixels(0)) {
        ProposalText("Alpha")
        ProposalText("Bravo")
        fixed("m", 20, 20, log)
    }.fixedSize().frame(width: Pixels(300), height: Pixels(300), alignment: .topLeading), log)
    let textRect = try markerY(VStack(alignment: .leading) {
        ProposalText("Alpha")
        fixed("m", 20, 20, log)
    }.fixedSize().frame(width: Pixels(300), height: Pixels(300), alignment: .topLeading), log)
    let textText = try markerY(VStack(alignment: .leading) {
        ProposalText("Alpha")
        ProposalText("Bravo")
        fixed("m", 20, 20, log)
    }.fixedSize().frame(width: Pixels(300), height: Pixels(300), alignment: .topLeading), log)
    let lineHeight = control / 2
    try #require(lineHeight > 0, "the control measured no text")
    try #require(textText != control, "default spacing and spacing 0 must disagree")
    #expect(textRect - lineHeight == 8, "text|rect gap (SwiftUI 8.15)")
    #expect(textText - textRect - lineHeight == 8, "text|text gap (SwiftUI 0)")
}

/// The deprecated spacing-first spellings, reached without a deprecation
/// warning: a requirement satisfied by a deprecated witness, called through the
/// protocol, keeps the 0-warning baseline.
@MainActor
private protocol SpacingFirstStacks {
    static func hStack<C: ProposalElementGroup>(spacing: Pixels, alignment: ProposalAlignment,
                                        @ElementBuilder content: () -> C) -> HStack<C>
    static func vStack<C: ProposalElementGroup>(spacing: Pixels, alignment: ProposalAlignment,
                                        @ElementBuilder content: () -> C) -> VStack<C>
}

@MainActor
private enum DeprecatedStackSpellings: SpacingFirstStacks {
    @available(*, deprecated)
    static func hStack<C: ProposalElementGroup>(spacing: Pixels, alignment: ProposalAlignment,
                                        @ElementBuilder content: () -> C) -> HStack<C> {
        HStack(spacing: spacing, alignment: alignment, content: content)
    }

    @available(*, deprecated)
    static func vStack<C: ProposalElementGroup>(spacing: Pixels, alignment: ProposalAlignment,
                                        @ElementBuilder content: () -> C) -> VStack<C> {
        VStack(spacing: spacing, alignment: alignment, content: content)
    }
}

/// CN-I's deprecated spacing-first initializers forward the caller's explicit
/// spacing and the cross-axis factor of the nine-case alignment unchanged.
///
/// - Stored values: for each of the nine `ProposalAlignment` cases,
///   `HStack(spacing: 20, alignment:)` stores spacing 20 and the case's
///   vertical factor as a `VerticalAlignment` (top 0, center ½, bottom 1), and
///   `VStack(spacing: 20, alignment:)` its horizontal factor as a
///   `HorizontalAlignment`.
/// - Placement, beside a spacer: `HStack(spacing: 20, alignment: .bottom){a
///   20×10; Spacer(minLength: 0); b 20×30}` places as the SwiftUI-order
///   `HStack(alignment: .bottom, spacing: 20)`: a at (0, 20), b at (60, 0)
///   (explicit spacing beside a spacer, SP4; A1's bottom). The control, the
///   same stack at default spacing and centre alignment, must disagree: a at
///   (0, 10), b at (20, 0). `VStack(spacing: 20, alignment: .trailing){a 10×20;
///   Spacer(minLength: 0); b 30×20}`: a at (20, 0), b at (0, 60), control a at
///   (10, 0), b at (0, 20).
///
/// Mutations: map factor 1 to `.center` in `VerticalAlignment(verticalFactorOf:)`
/// (M12); forward `spacing: nil` from the deprecated `HStack` initializer (M13).
@MainActor
@Test func theDeprecatedSpacingFirstStackInitializersForwardSpacingAndTheCrossFactor() throws {
    let spellings: any SpacingFirstStacks.Type = DeprecatedStackSpellings.self
    let nine: [(ProposalAlignment, VerticalAlignment, HorizontalAlignment)] = [
        (.topLeading, .top, .leading), (.top, .top, .center), (.topTrailing, .top, .trailing),
        (.leading, .center, .leading), (.center, .center, .center), (.trailing, .center, .trailing),
        (.bottomLeading, .bottom, .leading), (.bottom, .bottom, .center), (.bottomTrailing, .bottom, .trailing),
    ]
    for (alignment, vertical, horizontal) in nine {
        let h = spellings.hStack(spacing: Pixels(20), alignment: alignment) { fixed("e", 0, 0, BoundsLog()) }
        #expect(h.alignment == vertical, "HStack \(alignment)")
        #expect(h.spacing == Pixels(20), "HStack \(alignment) spacing")
        let v = spellings.vStack(spacing: Pixels(20), alignment: alignment) { fixed("e", 0, 0, BoundsLog()) }
        #expect(v.alignment == horizontal, "VStack \(alignment)")
        #expect(v.spacing == Pixels(20), "VStack \(alignment) spacing")
    }

    func render<Root: Element>(_ root: Root, _ width: Float, _ height: Float) {
        var root = root
        let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)), scaleFactor: 1)
        frame.render(&root)
    }
    do { // HStack
        let old = BoundsLog(), new = BoundsLog(), control = BoundsLog()
        render(spellings.hStack(spacing: Pixels(20), alignment: .bottom) {
            fixed("a", 20, 10, old); Spacer(minLength: Pixels(0)); fixed("b", 20, 30, old)
        }.fixedSize(), 80, 30)
        render(HStack(alignment: .bottom, spacing: Pixels(20)) {
            fixed("a", 20, 10, new); Spacer(minLength: Pixels(0)); fixed("b", 20, 30, new)
        }.fixedSize(), 80, 30)
        render(HStack {
            fixed("a", 20, 10, control); Spacer(minLength: Pixels(0)); fixed("b", 20, 30, control)
        }.fixedSize(), 40, 30)
        try #require(control.bounds["a"] != nil && new.bounds["a"] != nil)
        try #require(control.bounds["a"] != new.bounds["a"] && control.bounds["b"] != new.bounds["b"],
                     "the control must disagree with the SwiftUI-order spelling on both children")
        #expect(new.bounds["a"] == rect(0, 20, 20, 10), "HStack(alignment: .bottom, spacing: 20) a")
        #expect(new.bounds["b"] == rect(60, 0, 20, 30), "HStack(alignment: .bottom, spacing: 20) b")
        #expect(old.bounds["a"] == new.bounds["a"], "deprecated HStack a")
        #expect(old.bounds["b"] == new.bounds["b"], "deprecated HStack b")
    }
    do { // VStack
        let old = BoundsLog(), new = BoundsLog(), control = BoundsLog()
        render(spellings.vStack(spacing: Pixels(20), alignment: .trailing) {
            fixed("a", 10, 20, old); Spacer(minLength: Pixels(0)); fixed("b", 30, 20, old)
        }.fixedSize(), 30, 80)
        render(VStack(alignment: .trailing, spacing: Pixels(20)) {
            fixed("a", 10, 20, new); Spacer(minLength: Pixels(0)); fixed("b", 30, 20, new)
        }.fixedSize(), 30, 80)
        render(VStack {
            fixed("a", 10, 20, control); Spacer(minLength: Pixels(0)); fixed("b", 30, 20, control)
        }.fixedSize(), 30, 40)
        try #require(control.bounds["a"] != nil && new.bounds["a"] != nil)
        try #require(control.bounds["a"] != new.bounds["a"] && control.bounds["b"] != new.bounds["b"],
                     "the control must disagree with the SwiftUI-order spelling on both children")
        #expect(new.bounds["a"] == rect(20, 0, 10, 20), "VStack(alignment: .trailing, spacing: 20) a")
        #expect(new.bounds["b"] == rect(0, 60, 30, 20), "VStack(alignment: .trailing, spacing: 20) b")
        #expect(old.bounds["a"] == new.bounds["a"], "deprecated VStack a")
        #expect(old.bounds["b"] == new.bounds["b"], "deprecated VStack b")
    }
}

// MARK: - Lane 4: root, ZStack placement, overlay and background content, scroll axes (CN-J, CN-E, CN-K, CN-M)

/// Each probe leaf's DISTINCT proposals, in the order first asked. A class
/// shared by value into the `@Sendable` measure closures.
private final class ProposalRecord: @unchecked Sendable {
    var proposals: [String: [ProposedSize]] = [:]
    func record(_ name: String, _ proposal: ProposedSize) {
        if !(proposals[name, default: []].contains(proposal)) { proposals[name, default: []].append(proposal) }
    }
}

@MainActor
private final class Lane4Log {
    var bounds: [String: Bounds<Pixels>] = [:]
    var ids: [String: GlobalElementID] = [:]
    var taps: [String: Int] = [:]
    let record = ProposalRecord()
    func proposals(_ name: String) -> [ProposedSize] { record.proposals[name] ?? [] }
}

/// A native leaf answering `measure(proposal)`, logging its proposals and its
/// prepaint bounds under `name`.
private struct LaneProbe: ProposalElement {
    let name: String
    let log: Lane4Log
    let measure: @Sendable (ProposedSize) -> SizeD

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let (record, name, measure) = (log.record, self.name, self.measure)
        return (pass.requestNativeLeaf { proposal in
            record.record(name, proposal)
            return LayoutMeasurement(size: measure(proposal))
        }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        log.bounds[name] = bounds
        log.ids[name] = id
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

/// The probe's `fixed` leaf.
private func pFixed(_ name: String, _ width: Double, _ height: Double, _ log: Lane4Log) -> LaneProbe {
    LaneProbe(name: name, log: log) { _ in SizeD(width: width, height: height) }
}

/// The probe's `half` leaf: width half its proposal (half of 40 at nil), height 10.
private func pHalf(_ name: String, _ log: Lane4Log) -> LaneProbe {
    LaneProbe(name: name, log: log) { SizeD(width: ($0.width ?? 40) / 2, height: 10) }
}

/// The probe's greedy `Leaf(0..inf, ideal 10)` on both axes.
private func pGreedy(_ name: String, _ log: Lane4Log) -> LaneProbe {
    LaneProbe(name: name, log: log) { SizeD(width: $0.width ?? 10, height: $0.height ?? 10) }
}

/// The probe's `flexible ideal 50x300` scroll content: `proposal ?? ideal` per axis.
private func pFlexible(_ name: String, _ idealW: Double, _ idealH: Double, _ log: Lane4Log) -> LaneProbe {
    LaneProbe(name: name, log: log) { SizeD(width: $0.width ?? idealW, height: $0.height ?? idealH) }
}

private func pp(_ width: Double?, _ height: Double?) -> ProposedSize { ProposedSize(width: width, height: height) }

@MainActor
private func render<Root: Element>(_ root: Root, _ width: Float, _ height: Float,
                                   authority: LayoutAuthority = Frame.defaultLayoutAuthority) -> Frame {
    var root = root
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)), scaleFactor: 1,
                      layoutAuthority: authority)
    frame.render(&root)
    return frame
}

/// A root layout answering a fixed 58×20 over its content and recording the
/// proposal each `placeSubviews` receives: the only way to see the proposal a
/// window root is PLACED at (a leaf root never sees it).
private final class RootPlacementLog: @unchecked Sendable {
    var placements: [ProposedSize] = []
}

private struct RootPlacementRecorder: ProposalLayout {
    let log: RootPlacementLog
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 58, height: 20))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        log.placements.append(proposal)
    }
}

/// CN-J: a native window root is measured at the window's size and placed
/// CENTRED at its own answer; a greedy root fills.
///
/// - R control: a greedy root in 100×100 is proposed [100×100] and fills
///   (0, 0) 100×100.
/// - R1 `HStack(0){a 58x20}` root in 100×100: a at (21, 40) 58×20, and a
///   proposed only [100×100] — the root is PLACED at the window's proposal,
///   not at its answer. Seen through a custom root layout answering 58×20,
///   whose `placeSubviews` records [100×100] and whose bounds are (21, 40)
///   58×20. Mutation (verifier V2): place the root at proposal = its answer
///   (the recorder reads [58×20]).
/// - R2 a fixed 58×20 root: proposed [100×100], at (21, 40) 58×20.
/// - R3 fixed r 58×20 `.overlay{greedy a}`: r at (21, 40); a proposed
///   [58×20] at (21, 40) 58×20 — a root's overlay content is proposed the
///   ROOT's size. R4 the same through `.background`.
/// - Kernel half: `computeNativeLayout(root:proposal:centredIn:)` stores R2's
///   leaf at (21, 40) in (0, 0, 100, 100) and at (31, 60) in (10, 20, 100, 100).
///
/// Before the lane the root is stored at the full window: R1's a reads (0, 40)
/// and R2's leaf (0, 0) 100×100. Mutation: place at the full rect.
@MainActor
@Test func aNativeRootIsCentredAtItsAnswer() {
    do { // R control
        let log = Lane4Log()
        _ = render(pGreedy("a", log), 100, 100)
        #expect(log.proposals("a") == [pp(100, 100)], "R control proposals")
        #expect(log.bounds["a"] == rect(0, 0, 100, 100), "R control a")
    }
    do { // R1
        let log = Lane4Log()
        _ = render(HStack(spacing: Pixels(0)) { pFixed("a", 58, 20, log) }, 100, 100)
        #expect(log.bounds["a"] == rect(21, 40, 58, 20), "R1 a")
    }
    do { // R1, the root's placement proposal
        let log = Lane4Log()
        let placed = RootPlacementLog()
        _ = render(ProposalLayoutContainer(RootPlacementRecorder(log: placed)) { pFixed("a", 58, 20, log) },
                   100, 100)
        #expect(placed.placements == [pp(100, 100)], "R1 root placement proposal")
    }
    do { // R2
        let log = Lane4Log()
        _ = render(pFixed("a", 58, 20, log), 100, 100)
        #expect(log.proposals("a") == [pp(100, 100)], "R2 proposals")
        #expect(log.bounds["a"] == rect(21, 40, 58, 20), "R2 a")
    }
    do { // R3
        let log = Lane4Log()
        _ = render(pFixed("r", 58, 20, log).overlay { pGreedy("a", log) }, 100, 100)
        #expect(log.bounds["r"] == rect(21, 40, 58, 20), "R3 r")
        #expect(log.proposals("a") == [pp(58, 20)], "R3 a proposals")
        #expect(log.bounds["a"] == rect(21, 40, 58, 20), "R3 a")
    }
    do { // R4
        let log = Lane4Log()
        _ = render(pFixed("r", 58, 20, log).background { pGreedy("a", log) }, 100, 100)
        #expect(log.bounds["r"] == rect(21, 40, 58, 20), "R4 r")
        #expect(log.proposals("a") == [pp(58, 20)], "R4 a proposals")
        #expect(log.bounds["a"] == rect(21, 40, 58, 20), "R4 a")
    }
    do { // kernel half
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 58, height: 20)) }
        let answer = tree.computeNativeLayout(root: leaf, proposal: pp(100, 100),
                                              centredIn: LayoutRect(x: 0, y: 0, width: 100, height: 100))
        #expect(answer.size == SizeD(width: 58, height: 20), "kernel answer")
        #expect(tree.layout(leaf) == LayoutRect(x: 21, y: 40, width: 58, height: 20), "kernel R2")
        tree.computeNativeLayout(root: leaf, proposal: pp(100, 100),
                                 centredIn: LayoutRect(x: 10, y: 20, width: 100, height: 100))
        #expect(tree.layout(leaf) == LayoutRect(x: 31, y: 60, width: 58, height: 20), "kernel R2 offset")
    }
}

/// CN-K: several views in one `.overlay` or `.background` are a `ZStack` that
/// is CENTRED whatever the modifier's alignment; the alignment only positions
/// that `ZStack` in the primary. Every arm is a 60×40 window root, so the root
/// sits at the origin as the probe's arm does.
///
/// - A10 `primary 60x40 .overlay{o1 20x20; o2 30x10}`: o1 proposed [60×40,
///   30×20] at (20, 10); o2 at (15, 15) 30×10.
/// - K5a `.overlay{half h; o 20x20}`: h proposed [60×40, 30×20], at SwiftUI's
///   (17.5, 15) 15×10, stored rounded (18, 15); o at (15, 10). (K5b, an
///   explicit `ZStack`, reads the same and is the kernel's `ZStack` rule.)
/// - K5g `.overlay(alignment: .topLeading){half h; o}`: h at (2.5, 5) → (3, 5),
///   o at (0, 0).
/// - K5h `.background(alignment: .bottomTrailing){half h; o}`: h at
///   (32.5, 25) → (33, 25), o at (30, 20).
///
/// Before the lane an overlay of two views traps at `NativeOverlayModifier`'s
/// one-node precondition (measured filtered, never in the unfiltered suite:
/// shape 13) and `.background(alignment:content:)` does not exist. Mutation:
/// give the implicit `ZStack` the modifier's alignment (K5g moves).
@MainActor
@Test func severalViewsInAnOverlayOrBackgroundAreACentredZStackPositionedByTheAlignment() {
    do { // A10
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).overlay {
            pFixed("o1", 20, 20, log)
            pFixed("o2", 30, 10, log)
        }, 60, 40)
        #expect(log.proposals("o1") == [pp(60, 40), pp(30, 20)], "A10 o1 proposals")
        #expect(log.bounds["o1"] == rect(20, 10, 20, 20), "A10 o1")
        #expect(log.bounds["o2"] == rect(15, 15, 30, 10), "A10 o2")
    }
    do { // K5a
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).overlay { pHalf("h", log); pFixed("o", 20, 20, log) }, 60, 40)
        #expect(log.proposals("h") == [pp(60, 40), pp(30, 20)], "K5a h proposals")
        #expect(log.bounds["h"] == rect(18, 15, 15, 10), "K5a h (SwiftUI 17.5, 15)")
        #expect(log.bounds["o"] == rect(15, 10, 20, 20), "K5a o")
    }
    do { // K5g
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).overlay(alignment: .topLeading) {
            pHalf("h", log); pFixed("o", 20, 20, log)
        }, 60, 40)
        #expect(log.bounds["h"] == rect(3, 5, 15, 10), "K5g h (SwiftUI 2.5, 5)")
        #expect(log.bounds["o"] == rect(0, 0, 20, 20), "K5g o")
    }
    do { // K5h
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).background(alignment: .bottomTrailing) {
            pHalf("h", log); pFixed("o", 20, 20, log)
        }, 60, 40)
        #expect(log.bounds["h"] == rect(33, 25, 15, 10), "K5h h (SwiftUI 32.5, 25)")
        #expect(log.bounds["o"] == rect(30, 20, 20, 20), "K5h o")
        #expect(log.bounds["p"] == rect(0, 0, 60, 40), "K5h primary")
    }
}

/// CN-K: overlay and background content is PLACED at the primary's size as its
/// proposal, positioned by its answer. 60×40 window roots.
///
/// - K5 control `.overlay{half h}`: h proposed only [60×40], at (15, 15) 30×10.
///   The in-test control: the same leaf placed at its own answer (a 30×10
///   frame) answers 15 wide, so K5's 30 can tell the two rules apart.
/// - K5d `.overlay{HStack(0){half h; o 20x20}}`: the stack is re-solved at
///   60×40 — h at (10, 15) 20×10, o at (30, 10).
/// - K5f `.overlay{half h .frame(width: 30)}`: h proposed [30×40], at
///   (22.5, 15) → (23, 15) 15×10.
/// - K5e `.background{half h; o 20x20}`: as K5a — h (18, 15), o (15, 10).
/// - The `.background` halves of K5 and K5d read the overlay's numbers.
///
/// Green on arrival for the `.overlay` halves; `.background` is missing.
/// Mutation: place the content at its own answer (K5d moves).
@MainActor
@Test func overlayAndBackgroundContentIsPlacedAtThePrimarysSize() throws {
    let control = Lane4Log()
    _ = render(pHalf("h", control).frame(width: Pixels(30), height: Pixels(10)), 60, 40)
    do { // K5
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).overlay { pHalf("h", log) }, 60, 40)
        let h = try #require(log.bounds["h"]), c = try #require(control.bounds["h"])
        try #require(h.size.width != c.size.width, "K5 must differ from a leaf placed at its own answer")
        #expect(log.proposals("h") == [pp(60, 40)], "K5 h proposals")
        #expect(h == rect(15, 15, 30, 10), "K5 h")
    }
    do { // K5d
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).overlay {
            HStack(spacing: Pixels(0)) { pHalf("h", log); pFixed("o", 20, 20, log) }
        }, 60, 40)
        #expect(log.bounds["h"] == rect(10, 15, 20, 10), "K5d h")
        #expect(log.bounds["o"] == rect(30, 10, 20, 20), "K5d o")
    }
    do { // K5f
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).overlay { pHalf("h", log).frame(width: Pixels(30)) }, 60, 40)
        #expect(log.proposals("h") == [pp(30, 40)], "K5f h proposals")
        #expect(log.bounds["h"] == rect(23, 15, 15, 10), "K5f h (SwiftUI 22.5, 15)")
    }
    do { // K5e
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).background { pHalf("h", log); pFixed("o", 20, 20, log) }, 60, 40)
        #expect(log.proposals("h") == [pp(60, 40), pp(30, 20)], "K5e h proposals")
        #expect(log.bounds["h"] == rect(18, 15, 15, 10), "K5e h (SwiftUI 17.5, 15)")
        #expect(log.bounds["o"] == rect(15, 10, 20, 20), "K5e o")
    }
    do { // K5, background
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).background { pHalf("h", log) }, 60, 40)
        #expect(log.proposals("h") == [pp(60, 40)], "background K5 h proposals")
        #expect(log.bounds["h"] == rect(15, 15, 30, 10), "background K5 h")
    }
    do { // K5d, background
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).background {
            HStack(spacing: Pixels(0)) { pHalf("h", log); pFixed("o", 20, 20, log) }
        }, 60, 40)
        #expect(log.bounds["h"] == rect(10, 15, 20, 10), "background K5d h")
        #expect(log.bounds["o"] == rect(30, 10, 20, 20), "background K5d o")
    }
}

/// Element half of test 4.4 (CN-E's `ZStack` clause; the kernel half is in
/// `NativeStackDistributionTests.swift`), through a window root that CN-J
/// places at its answer.
///
/// - Z1 `ZStack{half h; o 20x20}` root in 60×40: answers 30×20, centred at
///   (15, 10); h placed at 30×20 answers 15×10 and sits at (2.5, 5) inside the
///   20×20 union → (17.5, 15) → stored (18, 15); o at (15, 10).
/// - Z4 `ZStack{half h; o 60x40}` root in 100×100: at (20, 30) 60×40; h
///   proposed [100×100, 60×40] at (35, 45) 30×10; o at (20, 30).
///
/// Before the lane the root is stored at the full window and each child placed
/// at the window's proposal: Z1's h reads (15, 15) 30×10. Mutations: as the
/// kernel half.
@MainActor
@Test func aZStackRootPlacesItsChildrenAtItsOwnSizeWithinTheirUnion() {
    do { // Z1
        let log = Lane4Log()
        _ = render(ZStack { pHalf("h", log); pFixed("o", 20, 20, log) }, 60, 40)
        #expect(log.proposals("h") == [pp(60, 40), pp(30, 20)], "Z1 h proposals")
        #expect(log.bounds["h"] == rect(18, 15, 15, 10), "Z1 h")
        #expect(log.bounds["o"] == rect(15, 10, 20, 20), "Z1 o")
    }
    do { // Z4
        let log = Lane4Log()
        _ = render(ZStack { pHalf("h", log); pFixed("o", 60, 40, log) }, 100, 100)
        #expect(log.proposals("h") == [pp(100, 100), pp(60, 40)], "Z4 h proposals")
        #expect(log.bounds["h"] == rect(35, 45, 30, 10), "Z4 h")
        #expect(log.bounds["o"] == rect(20, 30, 60, 40), "Z4 o")
    }
}

/// CN-K: an empty conditional in `.overlay` or `.background` leaves the primary
/// alone — A11 and A11b: the primary proposed [nil×nil] (here the window),
/// 60×40 at the origin — and registers no attachment: the tree holds the
/// primary's one node.
///
/// Before the lane the overlay traps at its one-node precondition and the
/// background API is missing. Mutation: register an attachment with a
/// zero-size leaf in the empty slot (the node count moves).
@MainActor
@Test func anEmptyOverlayOrBackgroundLeavesThePrimaryAlone() {
    let log = Lane4Log()
    let shows = log.bounds.count > 0
    do { // A11
        let frame = render(pFixed("p", 60, 40, log).overlay { if shows { pFixed("o", 20, 20, log) } }, 60, 40)
        #expect(log.bounds["o"] == nil, "A11 the conditional is empty")
        #expect(log.bounds["p"] == rect(0, 0, 60, 40), "A11 primary")
        #expect(frame.tree.nodeCount == 1, "A11 node count")
    }
    log.bounds = [:]
    do { // A11b
        let frame = render(pFixed("p", 60, 40, log).background { if shows { pFixed("b", 20, 20, log) } }, 60, 40)
        #expect(log.bounds["b"] == nil, "A11b the conditional is empty")
        #expect(log.bounds["p"] == rect(0, 0, 60, 40), "A11b primary")
        #expect(frame.tree.nodeCount == 1, "A11b node count")
    }
}

@MainActor
private final class TapCounter {
    var primary = 0
    var secondary = 0
}

@MainActor
private func click(_ platformWindow: FakePlatformWindow, at x: Float, _ y: Float) {
    let position = Point(x: Pixels(x), y: Pixels(y))
    platformWindow.simulateInput(.mouseDown(MouseEvent(position: position)))
    platformWindow.simulateInput(.mouseUp(MouseEvent(position: position)))
}

/// CN-K, overlay-presentation probe H1 and H2: a click over a view and its
/// `.background` content reaches the VIEW; outside the view it reaches the
/// background; an `.overlay`'s content takes both. Through a real `Window`,
/// 200×200: a 100×100 `onTap` primary, centred at (50, 50) by CN-J, and 150×150
/// `onTap` content centred on it at (25, 25). (100, 100) is over both; (35, 100)
/// is over the content only.
///
/// - H1 background: centre → primary 1, secondary 0; edge → primary 0,
///   secondary 1.
/// - H2 overlay (the control, which must disagree at the centre): centre →
///   secondary 1; edge → secondary 1.
///
/// Before the lane the background API is missing. Mutation: prepaint the
/// primary before the background content (the centre click reaches the
/// background).
@MainActor
@Test func aClickOverABackgroundAndItsPrimaryReachesThePrimary() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    func clicks(background: Bool, at x: Float, _ y: Float) throws -> (Int, Int) {
        let counter = TapCounter()
        func run<Root: Element>(_ content: @escaping @MainActor () -> Root) throws {
            let (window, platform) = try makeFakeWindow(device: device, size: 200, content: content)
            window.drawFrameIfNeeded()
            click(platform, at: x, y)
            window.drawFrameIfNeeded()
        }
        let primary = { Rectangle(width: Pixels(100), height: Pixels(100), color: .accent)
            .onTap { counter.primary += 1 } }
        let content = { Rectangle(width: Pixels(150), height: Pixels(150), color: .surface)
            .onTap { counter.secondary += 1 } }
        if background {
            try run { primary().background { content() } }
        } else {
            try run { primary().overlay { content() } }
        }
        return (counter.primary, counter.secondary)
    }
    let overlayCentre = try clicks(background: false, at: 100, 100)
    let backgroundCentre = try clicks(background: true, at: 100, 100)
    try #require(overlayCentre != backgroundCentre, "H2 (overlay) and H1 (background) must disagree at the centre")
    #expect(overlayCentre == (0, 1), "H2 centre")
    #expect(try clicks(background: false, at: 35, 100) == (0, 1), "H2 edge")
    #expect(backgroundCentre == (1, 0), "H1 centre")
    #expect(try clicks(background: true, at: 35, 100) == (0, 1), "H1 edge")
}

/// CN-K, probe A9: `.background(alignment:content:)` proposes the primary's
/// size and aligns like an overlay, and paints BENEATH the primary.
///
/// - A9 `primary 60x40 .background(alignment: .topLeading / .center /
///   .bottomTrailing){bg 20x20}`, 60×40 window roots: bg proposed [60×40], at
///   (0, 0) / (20, 10) / (40, 20).
/// - Scene order: a 60×40 `Rectangle` with a 20×20 `Rectangle` background emits
///   the 20×20 rect first; the same with `.overlay` (the control, which must
///   disagree) emits it last.
///
/// Before the lane the API is missing. Mutation: paint the content after the
/// primary.
@MainActor
@Test func aBackgroundIsProposedThePrimarysSizeAlignedAndPaintedBeneath() throws {
    let arms: [(ProposalAlignment, Float, Float)] = [(.topLeading, 0, 0), (.center, 20, 10), (.bottomTrailing, 40, 20)]
    for (alignment, x, y) in arms {
        let log = Lane4Log()
        _ = render(pFixed("p", 60, 40, log).background(alignment: alignment) { pFixed("bg", 20, 20, log) }, 60, 40)
        #expect(log.proposals("bg") == [pp(60, 40)], "A9 \(alignment) proposals")
        #expect(log.bounds["bg"] == rect(x, y, 20, 20), "A9 \(alignment) bg")
        #expect(log.bounds["p"] == rect(0, 0, 60, 40), "A9 \(alignment) primary")
    }
    func widths(_ frame: Frame) -> [Float] { frame.finalizedScene().rects.map { $0.bounds.size.width } }
    let primary = Rectangle(width: Pixels(60), height: Pixels(40), color: .accent)
    let secondary = Rectangle(width: Pixels(20), height: Pixels(20), color: .surface)
    let overlay = widths(render(primary.overlay { secondary }, 60, 40))
    let background = widths(render(primary.background { secondary }, 60, 40))
    try #require(overlay != background, "the overlay control must paint in a different order: \(overlay)")
    #expect(overlay == [60, 20], "overlay order")
    #expect(background == [20, 60], "background order")
}

@MainActor
private final class OnFlag {
    var value = true
}

/// A fixed-size native leaf with its own `@State`, incremented by a click, and
/// logged under `name` in prepaint (`taps` is the first property, so its slot
/// is `$state0`).
private struct TapLeaf: ProposalElement {
    @State var taps = 0
    var name: String
    var log: Lane4Log
    var width: Double
    var height: Double

    init(_ name: String, _ width: Double, _ height: Double, _ log: Lane4Log) {
        self.name = name
        self.log = log
        self.width = width
        self.height = height
    }

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let size = SizeD(width: width, height: height)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        log.bounds[name] = bounds
        log.ids[name] = id
        log.taps[name] = taps
        var handlers = Handlers()
        let state = _taps
        handlers.onClick = { state.wrappedValue += 1 }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {
        log.taps[name] = taps
    }
}

/// A proposal `Component` with no content: one cursor index, no node.
private struct EmptyContent: Component, ProposalElementGroup {
    var content: EmptyGroup { EmptyGroup() }
}

@MainActor
private func builderGroup<G: ElementGroup>(@ElementBuilder _ body: () -> G) -> G { body() }

/// CN-K / `MC-P` applied to `.background`: the content numbers from 0 under
/// `.child(of: modifier, at: -1)`, so its identity and `@State` do not depend
/// on how many indices the primary consumed (SwiftUI keeps an overlay's state
/// through such a flip, `docs/probes/swiftui-overlay-primary-shape.swift`).
///
/// Real `Window`, 100×100. The primary `{ if flag { EmptyContent() }; p 60x60 }`
/// is centred at (20, 20); the 100×100 background content fills the window, so
/// (90, 90) is the background alone. Three clicks there, then the flag flips
/// off and on. In-test control: p's own component reads `.positional(1)`,
/// `.positional(0)`, `.positional(1)`, proof the flip moved an index. The
/// content then reads `.positional(0)` under `.positional(-1)`, 3 taps, at
/// every step.
///
/// Before the lane the API is missing. Mutation: number the background content
/// under the primary's cursor.
@MainActor
@Test func aBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = Lane4Log()
    let flag = OnFlag()
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        builderGroup {
            if flag.value { EmptyContent() }
            TapLeaf("p", 60, 60, log)
        }
        .background { TapLeaf("b", 100, 100, log) }
    }
    window.drawFrameIfNeeded()
    try #require(log.bounds["p"] == rect(20, 20, 60, 60), "primary \(String(describing: log.bounds["p"]))")
    try #require(log.bounds["b"] == rect(0, 0, 100, 100), "background \(String(describing: log.bounds["b"]))")

    struct Reading: Equatable {
        var primary: PathComponent?
        var content: [PathComponent?]
        var taps: Int?
    }
    func reading() -> Reading {
        Reading(primary: log.ids["p"]?.component,
                content: [log.ids["b"]?.component, log.ids["b"]?.parent?.component], taps: log.taps["b"])
    }
    for _ in 0..<3 {
        click(platform, at: 90, 90)
        window.drawFrameIfNeeded()
    }
    let first = reading()
    flag.value = false
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let second = reading()
    flag.value = true
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let third = reading()

    try #require([first.primary, second.primary, third.primary] == [.positional(1), .positional(0), .positional(1)],
                 "the primary's shape did not flip")
    let kept = Reading(primary: nil, content: [.positional(0), .positional(-1)], taps: 3)
    for (label, r) in [("first", first), ("second", second), ("third", third)] {
        var half = r
        half.primary = nil
        #expect(half == kept, "\(label): \(r)")
    }
    #expect(log.taps["p"] == 0, "the primary was never clicked")
}

/// Probe A3, A4, A6: the nine alignments of a `ZStack` and of
/// `.overlay(alignment:)`, placed and sized as SwiftUI reads them. Each root is
/// in a 100×100 window, so a 60×40 answer is centred at (20, 30) (CN-J) and
/// the root's size is read through that offset.
///
/// - A3 `ZStack(alignment){big 60x40; small 20x20}`: big at (20, 30) 60×40
///   (the answer is the union); small at (20 + {0|20|40}, 30 + {0|10|20}).
/// - A4 `ZStack(.topLeading){a 60x20; b 20x40}`: answers the union 60×40, so a
///   sits at (20, 30).
/// - A6 `primary 60x40 .overlay(alignment){o 20x20}`: o proposed [60×40], at the
///   same nine positions.
///
/// Green on arrival for the placement (the kernel already agrees) except the
/// root's offset; requires `.topLeading` and `.bottomTrailing` to disagree.
/// Mutation: swap `horizontalFactor` for `verticalFactor` in the kernel's
/// `.overlay` placement (A3 moves).
@MainActor
@Test func everyZStackAndOverlayAlignmentPlacesAndSizesAsTheProbeReads() throws {
    let nine: [(ProposalAlignment, Float, Float)] = [
        (.topLeading, 0, 0), (.top, 20, 0), (.topTrailing, 40, 0),
        (.leading, 0, 10), (.center, 20, 10), (.trailing, 40, 10),
        (.bottomLeading, 0, 20), (.bottom, 20, 20), (.bottomTrailing, 40, 20),
    ]
    var positions: [String: Bounds<Pixels>] = [:]
    for (alignment, x, y) in nine {
        let log = Lane4Log()
        _ = render(ZStack(alignment: alignment) { pFixed("big", 60, 40, log); pFixed("small", 20, 20, log) },
                   100, 100)
        #expect(log.bounds["big"] == rect(20, 30, 60, 40), "A3 \(alignment) big")
        #expect(log.bounds["small"] == rect(20 + x, 30 + y, 20, 20), "A3 \(alignment) small")
        positions["\(alignment)"] = log.bounds["small"]

        let overlay = Lane4Log()
        _ = render(pFixed("p", 60, 40, overlay).overlay(alignment: alignment) { pFixed("o", 20, 20, overlay) },
                   100, 100)
        #expect(overlay.proposals("o") == [pp(60, 40)], "A6 \(alignment) proposals")
        #expect(overlay.bounds["o"] == rect(20 + x, 30 + y, 20, 20), "A6 \(alignment) o")
    }
    try #require(positions["topLeading"] != nil && positions["topLeading"] != positions["bottomTrailing"],
                 "the corners must disagree")
    do { // A4
        let log = Lane4Log()
        _ = render(ZStack(alignment: .topLeading) { pFixed("a", 60, 20, log); pFixed("b", 20, 40, log) }, 100, 100)
        #expect(log.bounds["a"] == rect(20, 30, 60, 20), "A4 a")
        #expect(log.bounds["b"] == rect(20, 30, 20, 40), "A4 b")
    }
}

/// CN-M: a `ProposalScrollView` answers its CONTENT's size on its non-scrolling
/// axis (and its proposal on the scrolling one).
///
/// - SC2 `.vertical{c fixed 50x30}` at 100×100 answers 50×100: as a 100×100
///   window root, centred at (25, 0), c at (25, 0). `.horizontal`: 100×30 at
///   (0, 35), c at (0, 35).
/// - SC4 `{c fixed 500x500}` at 100×100: `.vertical` 500×100 at (−200, 0);
///   `.horizontal` 100×500 at (0, −200).
/// - Kernel half: `newNativeScrollViewport` over a 50×30 leaf at 100×100
///   answers 50×100 (`.vertical`) and 100×30 (`.horizontal`).
///
/// Before the lane the viewport answers the proposal on both axes: SC2 reads
/// 100×100. Mutation: answer the proposal on the cross axis.
@MainActor
@Test func aProposalScrollViewAnswersItsContentOnItsNonScrollingAxis() {
    do {
        let log = Lane4Log()
        _ = render(ProposalScrollView(.vertical) { pFixed("c", 50, 30, log) }, 100, 100)
        #expect(log.bounds["c"] == rect(25, 0, 50, 30), "SC2 vertical")
    }
    do {
        let log = Lane4Log()
        _ = render(ProposalScrollView(.horizontal) { pFixed("c", 50, 30, log) }, 100, 100)
        #expect(log.bounds["c"] == rect(0, 35, 50, 30), "SC2 horizontal")
    }
    do {
        let log = Lane4Log()
        _ = render(ProposalScrollView(.vertical) { pFixed("c", 500, 500, log) }, 100, 100)
        #expect(log.bounds["c"] == rect(-200, 0, 500, 500), "SC4 vertical")
    }
    do {
        let log = Lane4Log()
        _ = render(ProposalScrollView(.horizontal) { pFixed("c", 500, 500, log) }, 100, 100)
        #expect(log.bounds["c"] == rect(0, -200, 500, 500), "SC4 horizontal")
    }
    for (axis, expected) in [(ProposalStackAxis.vertical, SizeD(width: 50, height: 100)),
                             (.horizontal, SizeD(width: 100, height: 30))] {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 50, height: 30)) }
        let viewport = tree.newNativeScrollViewport(child: leaf, axis: axis)
        let answer = tree.computeNativeLayout(root: viewport, proposal: pp(100, 100),
                                              in: LayoutRect(x: 0, y: 0, width: expected.width,
                                                             height: expected.height))
        #expect(answer.size == expected, "kernel SC2 \(axis)")
    }
}

/// CN-M, probe SCG2: content smaller than a single-axis viewport sits at the
/// LEADING edge of the scrolling axis. Each window is exactly the scroll view's
/// answer (so the root is at the origin): `.vertical{c 50x30}` in 50×100, c at
/// (0, 0); `.horizontal` in 100×30, c at (0, 0).
///
/// The control: the same content with a greedy sibling in a `ZStack` in 50×100
/// sits at y 35 (A5's centring), and must disagree with the vertical scroll
/// view. Green on arrival. Mutation: centre the content.
@MainActor
@Test func aProposalScrollViewPlacesSmallContentAtTheLeadingEdgeOfItsScrollingAxis() throws {
    let control = Lane4Log()
    _ = render(ZStack { pGreedy("g", control); pFixed("c", 50, 30, control) }, 50, 100)
    let vertical = Lane4Log()
    _ = render(ProposalScrollView(.vertical) { pFixed("c", 50, 30, vertical) }, 50, 100)
    let c = try #require(control.bounds["c"]), v = try #require(vertical.bounds["c"])
    try #require(c.origin.y == Pixels(35) && c != v, "the ZStack control reads \(c), the scroll view \(v)")
    #expect(v == rect(0, 0, 50, 30), "SCG2 vertical")
    let horizontal = Lane4Log()
    _ = render(ProposalScrollView(.horizontal) { pFixed("c", 50, 30, horizontal) }, 100, 30)
    #expect(horizontal.bounds["c"] == rect(0, 0, 50, 30), "SCG2 horizontal")
}

/// A custom layout that measures its only subview at fixed proposals and
/// records the answers; it answers 0×0 and places nothing.
private struct MeasuresAt: ProposalLayout {
    let proposals: [ProposedSize]
    let answers: AnswerRecord

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        answers.sizes = proposals.map { subviews[0].sizeThatFits($0).size }
        return LayoutMeasurement(size: .zero)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

private final class AnswerRecord: @unchecked Sendable {
    var sizes: [SizeD] = []
}

/// CN-M / CN-F, probe SC1: on its scrolling axis a `ProposalScrollView`
/// answers its proposal — the content's answer at nil, ∞ at ∞ — through the
/// element path. A custom layout measures the scroll view over `flexible ideal
/// 50x300` content at nil×nil, 100×100 and ∞×∞: 50×300, 100×100, ∞×∞ on
/// both axes.
///
/// Green on arrival for the kernel since lane 2; this pins the element path.
/// Mutation: answer the content at ∞.
@MainActor
@Test func aProposalScrollViewAnswersItsProposalOnItsScrollingAxis() {
    let inf = Double.infinity
    let expected = [SizeD(width: 50, height: 300), SizeD(width: 100, height: 100), SizeD(width: inf, height: inf)]
    for axis in [ScrollAxis.vertical, .horizontal] {
        let answers = AnswerRecord()
        let log = Lane4Log()
        _ = render(ProposalLayoutContainer(MeasuresAt(proposals: [pp(nil, nil), pp(100, 100), pp(inf, inf)],
                                                      answers: answers)) {
            ProposalScrollView(axis) { pFlexible("c", 50, 300, log) }
        }, 100, 100)
        #expect(answers.sizes == expected, "SC1 \(axis)")
    }
}

/// CN-H / CN-M, probe SC3: two direct children of a `ProposalScrollView` are a
/// centred, default-spaced `VStack` on either axis — a 50×30 and b 30×20, b at
/// (10, 38) from a.
///
/// 200×200 window roots: `.vertical` answers 50×200 (content width, CN-M),
/// centred at (75, 0): a (75, 0), b (85, 38). `.horizontal` answers 200×58,
/// at (0, 71): a (0, 71), b (10, 109).
///
/// Replaces `aProposalScrollViewStacksDirectChildrenWithSwiftUIsDefaultSpacing`
/// and `aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`.
/// Before the lane the horizontal arm answers 200×200 (a at (0, 0)). Mutation:
/// lower horizontally for `.horizontal`.
@MainActor
@Test func aProposalScrollViewsDirectChildrenAreACentredDefaultSpacedVStackOnEitherAxis() {
    do {
        let log = Lane4Log()
        _ = render(ProposalScrollView(.vertical) { pFixed("a", 50, 30, log); pFixed("b", 30, 20, log) }, 200, 200)
        #expect(log.bounds["a"] == rect(75, 0, 50, 30), "SC3 vertical a")
        #expect(log.bounds["b"] == rect(85, 38, 30, 20), "SC3 vertical b")
    }
    do {
        let log = Lane4Log()
        _ = render(ProposalScrollView(.horizontal) { pFixed("a", 50, 30, log); pFixed("b", 30, 20, log) }, 200, 200)
        #expect(log.bounds["a"] == rect(0, 71, 50, 30), "SC3 horizontal a")
        #expect(log.bounds["b"] == rect(10, 109, 30, 20), "SC3 horizontal b")
    }
}

/// `MC-L`'s item, reachable since CN-K lets one overlay hold several views: two
/// `ProposalScrollView`s in one overlay keep separate offsets, because each is
/// numbered under the overlay-side id (`MC-P`) and keys its `ScrollState` on
/// its own id.
///
/// Real `Window`, 100×100: a 100×100 primary; overlay `{ wide: vertical over
/// 100×400; narrow: vertical over 40×400 }`, a centred `ZStack` — wide at
/// (0, 0) 100×100, narrow at (30, 0) 40×100 (CN-M), on top. A wheel at (10, 50)
/// reaches only `wide`, one at (50, 50) only `narrow`.
///
/// Green on arrival by `MC-E`/`MC-P` once the overlay is allowed (before the
/// lane it traps). The first wheel's offset is required non-zero. Mutation:
/// key both `ScrollState`s on the parent id.
@MainActor
@Test func twoProposalScrollViewsInOneOverlayKeepSeparateOffsets() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        Rectangle(width: Pixels(100), height: Pixels(100), color: .surface).overlay {
            ProposalScrollView(.vertical, elementID: ElementID("wide")) {
                Rectangle(width: Pixels(100), height: Pixels(400), color: .accent)
            }
            ProposalScrollView(.vertical, elementID: ElementID("narrow")) {
                Rectangle(width: Pixels(40), height: Pixels(400), color: .accent)
            }
        }
    }
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    let side = GlobalElementID.child(of: root, at: -1, name: nil)
    let wide = GlobalElementID.child(of: side, at: 0, name: ElementID("wide"))
    let narrow = GlobalElementID.child(of: side, at: 1, name: ElementID("narrow"))
    func offsets() -> (Double, Double) {
        (window.stateTable.peek(wide, as: ScrollState.self)?.offset ?? 0,
         window.stateTable.peek(narrow, as: ScrollState.self)?.offset ?? 0)
    }
    window.drawFrameIfNeeded()
    platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: Pixels(10), y: Pixels(50)),
                                                    delta: Point(x: Pixels(0), y: Pixels(-37)))))
    window.drawFrameIfNeeded()
    let afterWide = offsets()
    try #require(afterWide.0 > 0, "the wheel over wide did not scroll it: \(afterWide)")
    #expect(afterWide.1 == 0, "narrow moved with wide: \(afterWide)")
    platform.simulateInput(.scrollWheel(ScrollEvent(position: Point(x: Pixels(50), y: Pixels(50)),
                                                    delta: Point(x: Pixels(0), y: Pixels(-20)))))
    window.drawFrameIfNeeded()
    let afterNarrow = offsets()
    #expect(afterNarrow.0 == afterWide.0, "wide moved with narrow: \(afterNarrow)")
    #expect(afterNarrow.1 > 0, "the wheel over narrow did not scroll it: \(afterNarrow)")
}

// MARK: - Lane 5: the legacy containers' three pinned divergences (CN-P)
//
// Each test builds a legacy container and its proposal counterpart side by
// side, `#require`s them to disagree by the probe's numbers, and so names the
// difference until task 7 (the owner of all three) lowers or deletes the legacy
// spelling. Probe arms are re-run 2026-09-16 from
// `docs/probes/swiftui-stack-algorithms.swift`, output identical on these arms.

/// A childless legacy leaf recording its prepaint bounds; `nil` sizes leave
/// that axis content-sized (0).
///
/// **Registers through `Frame`'s internal legacy registrar since stage 6a**
/// (record §38, disposition P-CSS): it is the legacy arm of three CSS-answer
/// pins, which pass `.legacy` explicitly so stage 6b's flip cannot reach them.
private struct LegacyMark: StyledElement {
    let name: String
    let log: Lane4Log
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()

    init(_ name: String, _ log: Lane4Log, width: Float? = nil, height: Float? = nil) {
        self.name = name
        self.log = log
        if let width { style.size.width = .length(.pixels(Pixels(width))) }
        if let height { style.size.height = .length(.pixels(Pixels(height))) }
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.frame.requestNode(style: style, children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log.bounds[name] = bounds
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// The gap between two logged rects along one axis: `b`'s leading edge minus
/// `a`'s trailing edge.
@MainActor
private func gap(_ log: Lane4Log, horizontal: Bool) throws -> Float {
    let a = try #require(log.bounds["a"]), b = try #require(log.bounds["b"])
    return horizontal
        ? b.origin.x.value - (a.origin.x.value + a.size.width.value)
        : b.origin.y.value - (a.origin.y.value + a.size.height.value)
}

/// **CN-P 1: a legacy `Row`/`Column` puts no space between two views where
/// `HStack`/`VStack` put 8.** Probe `S rect|rect`: `hstack 8  vstack 8` (and the
/// explicit control `hstack(0) 0`). Two 20×20 views, 100×100 window each.
///
/// Legacy: gap 0 on both axes. Proposal: 8 on both. Required to disagree.
/// Owner: task 7. Green on arrival (a pin). Mutation: `Row`/`Column` default
/// gap 8 (measured at design time, 22 tests redden; this one among them).
///
/// Pinned to the legacy authority by stage 6a (CSS, record §38 §4).
@MainActor
@Test func aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight() throws {
    let row = Lane4Log(), column = Lane4Log(), hStack = Lane4Log(), vStack = Lane4Log()
    _ = render(Row { LegacyMark("a", row, width: 20, height: 20); LegacyMark("b", row, width: 20, height: 20) },
               100, 100, authority: .legacy)
    _ = render(Column { LegacyMark("a", column, width: 20, height: 20); LegacyMark("b", column, width: 20, height: 20) },
               100, 100, authority: .legacy)
    _ = render(HStack { pFixed("a", 20, 20, hStack); pFixed("b", 20, 20, hStack) }, 100, 100)
    _ = render(VStack { pFixed("a", 20, 20, vStack); pFixed("b", 20, 20, vStack) }, 100, 100)

    let legacyH = try gap(row, horizontal: true), proposalH = try gap(hStack, horizontal: true)
    let legacyV = try gap(column, horizontal: false), proposalV = try gap(vStack, horizontal: false)
    try #require(legacyH != proposalH && legacyV != proposalV,
                 "the legacy and proposal stacks agree: \(legacyH)/\(proposalH), \(legacyV)/\(proposalV)")
    #expect(legacyH == 0 && legacyV == 0, "legacy Row/Column default gap: \(legacyH), \(legacyV)")
    #expect(proposalH == 8 && proposalV == 8, "S rect|rect: \(proposalH), \(proposalV)")
}

/// **CN-P 2: a legacy `Stack` offers its child fit-content where a `ZStack`
/// offers its proposal.** Probe `A5`: `ZStack{a 0..inf ideal 10; b 20x20}` at
/// 100×80 answers 100×80 with a at (0, 0) 100×80 and b at (40, 30). The legacy
/// `Stack` in a 100×80 window places a sizeless leaf at (50, 40) 0×0 (its
/// fit-content), and a 20×20 sibling at (40, 30) — where both agree.
///
/// Owner: task 7. Green on arrival (a pin). Mutation: set the legacy `Stack`
/// container's `alignItems` and `justifyItems` to `.stretch` in `Stack.init`
/// (measured at design time: 7 tests redden and the child reads (0, 0) 100×80;
/// this pin must be the 8th).
///
/// Pinned to the legacy authority by stage 6a (CSS, record §38 §4).
@MainActor
@Test func aLegacyStackOffersFitContentWhereAZStackOffersItsProposal() throws {
    let legacy = Lane4Log(), proposal = Lane4Log()
    _ = render(Stack { LegacyMark("a", legacy); LegacyMark("b", legacy, width: 20, height: 20) }, 100, 80,
               authority: .legacy)
    _ = render(ZStack { pGreedy("a", proposal); pFixed("b", 20, 20, proposal) }, 100, 80)

    let legacyA = try #require(legacy.bounds["a"]), proposalA = try #require(proposal.bounds["a"])
    try #require(legacyA != proposalA, "the legacy Stack and the ZStack offered alike: \(legacyA)")
    #expect(legacyA == rect(50, 40, 0, 0), "legacy Stack, sizeless child: \(legacyA)")
    #expect(proposalA == rect(0, 0, 100, 80), "A5 a: \(proposalA)")
    #expect(legacy.bounds["b"] == rect(40, 30, 20, 20) && proposal.bounds["b"] == rect(40, 30, 20, 20),
            "A5 b, where both agree")
}

/// **CN-P 3: a legacy `ScrollView`'s viewport takes its parent's cross axis
/// where a `ProposalScrollView` takes its content's.** Probe `SC2`:
/// `ScrollView(.vertical){c fixed 50x30}` at 100×100 answers **50**×100. Read as
/// the registered scroll region's width, 100×100 window root: legacy 100,
/// proposal 50 (centred at x 25 by `CN-J`).
///
/// Owner: task 7. Green on arrival (a pin, after lane 4). Mutation: revert lane
/// 4's cross-axis line (the proposal viewport answers its proposal).
///
/// Pinned to the legacy authority by stage 6a (CSS, record §38 §4).
@MainActor
@Test func aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents() throws {
    let legacy = Lane4Log(), proposal = Lane4Log()
    let legacyFrame = render(ScrollView(.vertical) { LegacyMark("c", legacy, width: 50, height: 30) }, 100, 100,
                             authority: .legacy)
    let proposalFrame = render(ProposalScrollView(.vertical) { pFixed("c", 50, 30, proposal) }, 100, 100)

    let legacyRegion = try #require(legacyFrame.scrollRegions.first).bounds
    let proposalRegion = try #require(proposalFrame.scrollRegions.first).bounds
    try #require(legacyRegion.size.width != proposalRegion.size.width,
                 "both viewports are \(legacyRegion.size.width) wide")
    #expect(legacyRegion == rect(0, 0, 100, 100), "legacy viewport: \(legacyRegion)")
    #expect(proposalRegion == rect(25, 0, 50, 100), "SC2 vertical viewport: \(proposalRegion)")
}
