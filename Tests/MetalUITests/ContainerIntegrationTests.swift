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

/// Lane 2 through the element API (CN-C, CN-F).
///
/// - SP1 `HStack(spacing: 0){a20; Spacer(); b20}` under `.fixedSize()` (so
///   the stack is proposed nil×nil, as the probe's arm is): b at x 28, the
///   default minimum 8.
/// - G4 `HStack(spacing: 0){a fixed 20; b fixed 20 .frame(maxWidth:
///   .infinity)}`, a 200×50 window root: b centred in 180 at x 100 (y 15: the
///   root is stored at the full window until lane 4's CN-J). Revision 5's G4r,
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
        #expect(log.bounds["a"] == rect(0, 0, 20, 20), "SP1 a")
        #expect(log.bounds["b"] == rect(28, 0, 20, 20), "SP1 b")
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
/// proposed nil×nil as the probe's arm is, and sits at the origin).
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
        #expect(log.bounds["b"] == rect(28, 0, 20, 20), "element S rect|rect hstack b")
        render(VStack { fixed("c", 20, 20, log); fixed("d", 20, 20, log) }.fixedSize())
        #expect(log.bounds["d"] == rect(0, 28, 20, 20), "element S rect|rect vstack b")
    }
    do { // SP2
        let log = BoundsLog()
        render(HStack { fixed("a", 20, 20, log); Spacer(); fixed("b", 20, 20, log) }.fixedSize())
        #expect(log.bounds["b"] == rect(28, 0, 20, 20), "element SP2 b")
    }
    do { // SP3
        let log = BoundsLog()
        render(HStack { fixed("a", 20, 20, log); Spacer(minLength: Pixels(0)); fixed("b", 20, 20, log) }.fixedSize())
        #expect(log.bounds["b"] == rect(20, 0, 20, 20), "element SP3 b")
    }
    do { // SP7
        let log = BoundsLog()
        render(VStack { fixed("a", 20, 20, log); Spacer(minLength: Pixels(0)); fixed("b", 20, 20, log) }.fixedSize())
        #expect(log.bounds["b"] == rect(0, 20, 20, 20), "element SP7 b")
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
        #expect(log.bounds["b"] == rect(28, 0, 20, 20), "element G23 b")
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
    #expect(log.bounds["b4"] == rect(60, 0, 20, 20), "SP4 b")

    render(HStack(spacing: Pixels(0)) { fixed("a", 20, 20, log); fixed("b0", 20, 20, log) }.fixedSize())
    #expect(log.bounds["b0"] == rect(20, 0, 20, 20), "S control hstack(0) b")
    render(HStack(spacing: Pixels(20)) { fixed("a", 20, 20, log); fixed("b20", 20, 20, log) }.fixedSize())
    #expect(log.bounds["b20"] == rect(40, 0, 20, 20), "S control hstack(20) b")
    render(VStack(spacing: Pixels(20)) { fixed("a", 20, 20, log); fixed("v20", 20, 20, log) }.fixedSize())
    #expect(log.bounds["v20"] == rect(0, 40, 20, 20), "S control vstack(20) b")
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
/// Three `VStack(alignment: .leading)` roots under `.fixedSize()`, the marker
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
    }.fixedSize(), log)
    let textRect = try markerY(VStack(alignment: .leading) {
        ProposalText("Alpha")
        fixed("m", 20, 20, log)
    }.fixedSize(), log)
    let textText = try markerY(VStack(alignment: .leading) {
        ProposalText("Alpha")
        ProposalText("Bravo")
        fixed("m", 20, 20, log)
    }.fixedSize(), log)
    let lineHeight = control / 2
    try #require(lineHeight > 0, "the control measured no text")
    try #require(textText != control, "default spacing and spacing 0 must disagree")
    #expect(textRect - lineHeight == 8, "text|rect gap (SwiftUI 8.15)")
    #expect(textText - textRect - lineHeight == 8, "text|text gap (SwiftUI 0)")
}
