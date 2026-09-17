import Testing
import MetalUICore
import MetalUILayout

// Lane 2 ("boundaries") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`.
// Rulings SA-G (mixing is rejected in every direction), SA-H (the invalidation
// contract) and SA-I (one `isLayingOut` flag for both engines), in
// `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`.
//
// **A plain import on purpose**: every entry point these tests touch is public,
// so the traps are what an outside module meets (practices shape 16 is about
// the converse, and the plain import costs nothing here).
//
// **Each test asserts its message fragment on stderr as well as `.failure`**,
// because a trap elsewhere must not pass: several arms below die anyway before
// their check exists (a stack overflow, a stale-id precondition), and only the
// fragment tells those deaths from the trap each test is named for
// (`ElementGroupTrapTests.swift`'s note). Exit-test bodies are non-capturing,
// so each arm is its own test.

/// The tree and one node a layout-time arm reaches from inside a measure
/// closure, at **file scope on purpose**, as in `LayoutContextTests`'
/// re-entrancy test: an exit-test body may not capture, and a measure closure
/// is `@Sendable` while `LayoutTree` is not. Written once and read from one
/// subprocess.
nonisolated(unsafe) private var boundaryTree: LayoutTree?
nonisolated(unsafe) private var boundaryNode: LayoutNodeID?

private let space = AvailableSpaceSize(width: .definite(100), height: .definite(100))
private let proposal = ProposedSize(width: 100, height: 100)
private let bounds = LayoutRect(x: 0, y: 0, width: 100, height: 100)

private struct PassThroughLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 10, height: 10))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

// MARK: - Mixing, in every direction (SA-G)

/// A native node handed to a legacy `newNode` as a child traps at registration.
/// Before this check the CSS engine laid the native node out as an empty flex
/// box: its measure never ran and it was stored at a centred 0×0 (the design's
/// evidence 4).
@Test func aNativeNodeRegisteredUnderALegacyNodeTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let native = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) }
        _ = tree.newNode(style: Style(), children: [native])
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("given a native child"),
            "aborted, but not at the native-child check this test is about:\n\(stderr)")
}

/// A legacy node handed to a native stack traps at registration. The check
/// predates this lane (`nativeNode(_:)`) and had no test.
@Test func aLegacyNodeRegisteredUnderANativeStackTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let legacy = tree.newNode(style: Style(), children: [])
        _ = tree.newNativeLinearStack(children: [legacy], axis: .horizontal)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("contains a legacy node"),
            "aborted, but not at the legacy-child check this test is about:\n\(stderr)")
}

/// The same for the one protocol-backed registrar, `newNativeLayout`.
@Test func aLegacyNodeRegisteredUnderACustomLayoutTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let legacy = tree.newNode(style: Style(), children: [])
        _ = tree.newNativeLayout(PassThroughLayout(), children: [legacy])
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("contains a legacy node"),
            "aborted, but not at the legacy-child check this test is about:\n\(stderr)")
}

/// The positive control for the native-child check: all twelve native
/// registrars accept native children without trapping. They must not route
/// through the checking `newNode`, because every one of them hands native
/// children to the storage append.
///
/// The `precondition`s confirm every registrar still appends one storage row
/// with a `Style.default`, since that row is what `nodeCount` and `style(_:)`
/// read.
@Test func everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping() async {
    await #expect(processExitsWith: .success) {
        let tree = LayoutTree(generation: 0)
        func leaf() -> LayoutNodeID {
            tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) }
        }
        var ids: [LayoutNodeID] = []
        ids.append(leaf())                                                           // 1 newNativeLeaf
        ids.append(tree.newNativeOverlay(children: [leaf(), leaf()]))                // 2 newNativeOverlay
        ids.append(tree.newNativeOverlayAttachment(child: leaf(), overlay: leaf()))  // 3
        ids.append(tree.newNativeFrame(child: leaf(), width: 10))                    // 4
        ids.append(tree.newNativePadding(child: leaf(), insets: Edges(all: 1)))      // 5
        ids.append(tree.newNativeFixedSize(child: leaf()))                           // 6
        ids.append(tree.newNativeAspectRatio(child: leaf(), ratio: 2))               // 7
        ids.append(tree.newNativeLayoutPriority(child: leaf(), priority: 1))         // 8
        ids.append(tree.newNativeSpacer())                                           // 9
        ids.append(tree.newNativeLinearStack(children: [leaf(), leaf()], axis: .vertical)) // 10
        ids.append(tree.newNativeScrollViewport(child: leaf(), axis: .vertical))     // 11
        ids.append(tree.newNativeLayout(PassThroughLayout(), children: [leaf(), leaf()])) // 12
        // 12 registered nodes plus 14 leaves registered as their children.
        precondition(tree.nodeCount == 26, "node count \(tree.nodeCount)")
        for id in ids {
            precondition(tree.isNativeLayoutNode(id))
            precondition(tree.style(id) == .default)
        }
    }
}

/// Legacy `computeLayout` handed a native root traps. Before this check flex
/// ran over the native root's placeholder `Style.default` and exited cleanly.
@Test func computeLayoutRejectsANativeRoot() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let native = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) }
        computeLayout(tree, root: native, available: space)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("called on a native root"),
            "aborted, but not at the native-root check this test is about:\n\(stderr)")
}

/// A `Style` written onto a native node traps, outside any layout. The
/// proposal engine never reads it, so before this check the write was silently
/// inert (`StyledComponent`'s path, ruling SA-G).
@Test func aStyleWrittenOntoANativeNodeTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let native = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) }
        tree.setStyle(native, Style())
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("setStyle on a native layout node"),
            "aborted, but not at the native-style check this test is about:\n\(stderr)")
}

// MARK: - Re-entrancy and mutation during a layout call (SA-I, SA-H clause 7)

/// A native measure closure that lays out the tree it is being measured in
/// traps at `beginLayout`. Before the native entry point held the flag, the
/// nested call re-measured the same leaf, which re-entered again, until the
/// stack ran out with no attribution.
@Test func computeNativeLayoutReenteredFromAMeasureClosureTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        boundaryTree = tree
        let leaf = tree.newNativeLeaf { _ in
            if let t = boundaryTree, let r = boundaryNode {
                t.computeNativeLayout(root: r, proposal: proposal, in: bounds)
            }
            return LayoutMeasurement(size: SizeD(width: 5, height: 5))
        }
        let root = tree.newNativeOverlay(children: [leaf])
        boundaryNode = root
        tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("re-entered on the same tree"),
            "aborted, but not at the re-entrancy check this test is about:\n\(stderr)")
}

/// A native measure closure that runs LEGACY layout over a separate legacy
/// root in the same tree traps: one flag covers both engines (ruling SA-I).
@Test func computeLayoutCalledFromANativeMeasureClosureTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        boundaryTree = tree
        boundaryNode = tree.newNode(style: Style(), children: [])
        let leaf = tree.newNativeLeaf { _ in
            if let t = boundaryTree, let legacy = boundaryNode {
                computeLayout(t, root: legacy, available: space)
            }
            return LayoutMeasurement(size: SizeD(width: 5, height: 5))
        }
        let root = tree.newNativeOverlay(children: [leaf])
        tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("re-entered on the same tree"),
            "aborted, but not at the re-entrancy check this test is about:\n\(stderr)")
}

/// `setStyle`'s existing precondition now fires during NATIVE layout, on a
/// legacy node of the same tree, because the native entry point holds the flag.
@Test func setStyleOnALegacyNodeDuringNativeLayoutTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        boundaryTree = tree
        boundaryNode = tree.newNode(style: Style(), children: [])
        let leaf = tree.newNativeLeaf { _ in
            if let t = boundaryTree, let legacy = boundaryNode {
                t.setStyle(legacy, Style())
            }
            return LayoutMeasurement(size: SizeD(width: 5, height: 5))
        }
        let root = tree.newNativeOverlay(children: [leaf])
        tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("setStyle called while"),
            "aborted, but not at the layout-time style check this test is about:\n\(stderr)")
}

/// Registering a native node from inside native layout traps: it grows the
/// arrays the run is indexing.
@Test func registeringANativeNodeDuringNativeLayoutTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        boundaryTree = tree
        let leaf = tree.newNativeLeaf { _ in
            _ = boundaryTree?.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }
            return LayoutMeasurement(size: SizeD(width: 5, height: 5))
        }
        let root = tree.newNativeOverlay(children: [leaf])
        tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("registered while layout is running"),
            "aborted, but not at the registration check this test is about:\n\(stderr)")
}

/// Registering a LEGACY leaf from inside native layout traps too: `newLeaf`
/// reaches the same storage append as every native registrar.
@Test func registeringALegacyLeafDuringNativeLayoutTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        boundaryTree = tree
        let leaf = tree.newNativeLeaf { _ in
            _ = boundaryTree?.newLeaf(style: Style()) { _, _ in SizeD(width: 1, height: 1) }
            return LayoutMeasurement(size: SizeD(width: 5, height: 5))
        }
        let root = tree.newNativeOverlay(children: [leaf])
        tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("registered while layout is running"),
            "aborted, but not at the registration check this test is about:\n\(stderr)")
}

/// Registering a node from inside LEGACY layout traps: the registration check
/// is not native-only.
@Test func registeringANodeDuringLegacyLayoutTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        boundaryTree = tree
        // An `auto`-sized leaf in a row, so the flex engine consults the
        // measure function (`LayoutContextTests`' re-entrancy test's shape).
        let leaf = tree.newLeaf(style: Style()) { _, _ in
            _ = boundaryTree?.newNode(style: Style(), children: [])
            return SizeD(width: 10, height: 10)
        }
        var rootStyle = Style()
        rootStyle.flexDirection = .row
        let root = tree.newNode(style: rootStyle, children: [leaf])
        computeLayout(tree, root: root, available: space)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("registered while layout is running"),
            "aborted, but not at the registration check this test is about:\n\(stderr)")
}

/// `reset(generation:)` from inside layout traps with its own message. Before
/// the check it emptied the arrays mid-run and the run died on the next
/// stale-id or out-of-range read, with a message about neither.
@Test func resettingATreeDuringLayoutTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        boundaryTree = tree
        let leaf = tree.newNativeLeaf { _ in
            boundaryTree?.reset(generation: 1)
            return LayoutMeasurement(size: SizeD(width: 5, height: 5))
        }
        let root = tree.newNativeOverlay(children: [leaf])
        tree.computeNativeLayout(root: root, proposal: proposal, in: bounds)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("reset(generation:) called while layout is running"),
            "aborted, but not at the reset check this test is about:\n\(stderr)")
}

/// A measure closure writing a rect traps: measurement never writes a rect
/// (ruling SA-H clause 4). The closure runs inside `measureNative`'s
/// `measureDepth` bracket, which is what the check reads.
///
/// **The leaf is the ROOT, on purpose.** Under a parent the closure also runs
/// inside the parent's bracket, so a leaf case that raised `measureDepth` only
/// after calling its closure still trapped here. Measured: with the leaf under
/// an overlay, that mutation left this test green; as the root, the closure
/// runs at depth 0 unless the leaf's own bracket holds.
@Test func writingARectDuringNativeMeasurementTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        boundaryTree = tree
        let leaf = tree.newNativeLeaf { _ in
            if let t = boundaryTree, let node = boundaryNode {
                t.setLayout(node, LayoutRect(x: 1, y: 2, width: 3, height: 4))
            }
            return LayoutMeasurement(size: SizeD(width: 5, height: 5))
        }
        boundaryNode = leaf
        tree.computeNativeLayout(root: leaf, proposal: proposal, in: bounds)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("during native measurement"),
            "aborted, but not at the measurement rect-write check this test is about:\n\(stderr)")
}

// MARK: - One node, one parent, at every registrar (CN-L)

/// The registrars `aNativeRegistrarWithChildrenRejectsANodeThatAlreadyHasAParent`
/// walks, in `LayoutTree.swift`'s `recordParent` call order.
private let registrarNames = ["linearStack", "frame", "overlayAttachment", "padding", "fixedSize", "aspectRatio", "layoutPriority", "scrollViewport", "overlay", "custom"]

/// Registers a leaf under a native frame (which records the parent), then
/// registers a second node of kind `registrar` whose child is that SAME leaf
/// when `sharingTheLeaf`, or a fresh leaf otherwise, and lays the second node
/// out. A file-scope function taking only literals, because an exit-test body
/// may not capture.
private func registerALeafUnderAFrameThenUnder(registrar: Int, sharingTheLeaf: Bool) {
    let tree = LayoutTree(generation: 0)
    let first = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
    _ = tree.newNativeFrame(child: first, width: 20, height: 20)
    let child = sharingTheLeaf
        ? first
        : tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
    let other = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) }
    let second: LayoutNodeID
    switch registrar {
    case 0: second = tree.newNativeLinearStack(children: [child], axis: .horizontal)
    case 1: second = tree.newNativeFrame(child: child, width: 30, height: 30)
    case 2: second = tree.newNativeOverlayAttachment(child: child, overlay: other)
    case 3: second = tree.newNativePadding(child: child, insets: Edges(top: 1, right: 1, bottom: 1, left: 1))
    case 4: second = tree.newNativeFixedSize(child: child)
    case 5: second = tree.newNativeAspectRatio(child: child, ratio: 2)
    case 6: second = tree.newNativeLayoutPriority(child: child, priority: 1)
    case 7: second = tree.newNativeScrollViewport(child: child, axis: .vertical)
    case 8: second = tree.newNativeOverlay(children: [child])
    default: second = tree.newNativeLayout(PassThroughLayout(), children: [child])
    }
    tree.computeNativeLayout(root: second, proposal: proposal, in: bounds)
}

/// **Ruling CN-L at each of the ten native registrars with children**: a node
/// that already has a native parent (here a frame) traps when a second
/// registrar of each kind lists it, with the parent record's message.
/// `aNativeNodeRegisteredTwiceTraps` (`ProposalNodeIDTests.swift`) reaches
/// only the stack and frame sites through the element API.
///
/// Positive control, in process: each registrar over a FRESH leaf registers
/// and lays out without trapping, so every arm's death is the shared leaf's.
///
/// Mutation (verifier V7): delete `recordParent` from the eight registrars
/// other than the linear stack and frame; each of their arms exits successfully.
@Test func aNativeRegistrarWithChildrenRejectsANodeThatAlreadyHasAParent() async {
    for registrar in registrarNames.indices {
        registerALeafUnderAFrameThenUnder(registrar: registrar, sharingTheLeaf: false)
    }
    do { // linearStack
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 0, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "linearStack: aborted, but not at the parent record:\n\(stderr)")
    }
    do { // frame
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 1, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "frame: aborted, but not at the parent record:\n\(stderr)")
    }
    do { // overlayAttachment
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 2, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "overlayAttachment: aborted, but not at the parent record:\n\(stderr)")
    }
    do { // padding
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 3, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "padding: aborted, but not at the parent record:\n\(stderr)")
    }
    do { // fixedSize
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 4, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "fixedSize: aborted, but not at the parent record:\n\(stderr)")
    }
    do { // aspectRatio
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 5, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "aspectRatio: aborted, but not at the parent record:\n\(stderr)")
    }
    do { // layoutPriority
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 6, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "layoutPriority: aborted, but not at the parent record:\n\(stderr)")
    }
    do { // scrollViewport
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 7, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "scrollViewport: aborted, but not at the parent record:\n\(stderr)")
    }
    do { // overlay
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 8, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "overlay: aborted, but not at the parent record:\n\(stderr)")
    }
    do { // custom
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            registerALeafUnderAFrameThenUnder(registrar: 9, sharingTheLeaf: true)
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("MC-G hole 4"), "custom: aborted, but not at the parent record:\n\(stderr)")
    }
}
