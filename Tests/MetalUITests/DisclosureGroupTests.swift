import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI

// Lane 1 of the hierarchical lists: `DisclosureGroup` in an eager context (rulings `OG-A`, `OG-D`, `OG-H`, `OG-J`, `OG-F`;
// probe `docs/probes/swiftui-disclosure-group.swift`, arms D1-D4). The geometry literals below are D1's recorded values.
//
// The fixture is the probe's: a `VStack(alignment: .leading, spacing: 0)` 260 wide holding a 37 wide "above" bar, the
// group, and a 36 wide "below" bar (SwiftUI's two 16 high Texts, drawn as bars so no font enters the numbers); the group's
// own frame is read as the gap between the two bars.

@MainActor private func bar(_ w: Float, _ h: Float = 16) -> some ProposalElementGroup {
    Color(.accent).frame(width: Pixels(w), height: Pixels(h))
}

/// Everything a test reads about a stage frame.
@MainActor private struct Stage {
    let all: [GlobalElementID: Bounds<Pixels>]
    init(frame: Frame) { all = frame.elementBounds }
    init(window: Window) { all = window.lastElementBounds }
    private func bounds(width: Float, height: Float = 16) -> Bounds<Pixels>? {
        let found = all.values.filter { $0.size.width.value == width && $0.size.height.value == height }
        return found.first
    }
    var above: Bounds<Pixels> { bounds(width: 37)! }
    var below: Bounds<Pixels> { bounds(width: 36)! }
    /// The group's height: from the bottom of "above" to the top of "below" (spacing 0).
    var groupHeight: Float { below.origin.y.value - (above.origin.y.value + above.size.height.value) }
    var groupTop: Float { above.origin.y.value + above.size.height.value }
    var content1: Bounds<Pixels>? { bounds(width: 75) }
    var content2: Bounds<Pixels>? { bounds(width: 74) }
}

@MainActor private func stageTree<G: ElementGroup>(@ElementBuilder group: () -> G) -> some Element {
    let built = group()
    return VStack(alignment: .leading, spacing: Pixels(0)) {
        bar(37)
        built
        bar(36)
    }
    .frame(width: Pixels(260))
}

@MainActor private func render(_ isExpanded: Bool, title: String = "Section") throws -> Stage {
    let root = stageTree {
        DisclosureGroup(isExpanded: .constant(isExpanded)) {
            bar(75); bar(74)
        } label: { Text(title) }
    }
    return Stage(frame: try controlRender(root, width: 300, height: 200))
}

@MainActor private final class Flag {
    var open = false
    var writes: [Bool] = []
    var binding: Binding<Bool> { Binding(get: { self.open }, set: { self.open = $0; self.writes.append($0) }) }
}

@MainActor private final class Counter { var calls = 0 }

// MARK: - Geometry (D1)

/// **D1.** A collapsed group is 260 x 24 (the label row), expanded 260 x 56: 24 + two 16 high children, 0 spacing, the first
/// directly under the row. Mutations: row height 24 -> 25; a gap between the row and its content.
@Test @MainActor func aGroupIsA24PointRowCollapsedAndRowPlusContentExpanded() throws {
    let collapsed = try render(false), expanded = try render(true)
    #expect(collapsed.groupHeight == 24, "collapsed 24 (D1): \(collapsed.groupHeight)")
    #expect(expanded.groupHeight == 56, "expanded 24 + 16 + 16 (D1): \(expanded.groupHeight)")
    #expect(collapsed.content1 == nil && collapsed.content2 == nil, "a collapsed group builds no content")
    let c1 = try #require(expanded.content1), c2 = try #require(expanded.content2)
    #expect(c1.origin.y.value - expanded.groupTop == 24, "the first child is at +24 (D1)")
    #expect(c2.origin.y.value - (c1.origin.y.value + c1.size.height.value) == 0, "0 spacing between children (D1)")
    // The group is the stack's 260 wide: the label row's frame is 260 x 24.
    let rows = expanded.all.values.filter { $0.size.width.value == 260 && $0.size.height.value == 24 }
    #expect(!rows.isEmpty, "a 260 x 24 label row exists (D1)")
}

/// **D1.** No indentation: the content is a centre-aligned stack in the group's width, (260 - 75) / 2 and (260 - 74) / 2
/// from the leading edge (the probe's 92.5 and 93).
@Test @MainActor func theContentIsCentredInTheGroupsWidthWithNoIndentation() throws {
    let expanded = try render(true)
    let c1 = try #require(expanded.content1), c2 = try #require(expanded.content2)
    let left = expanded.above.origin.x.value
    #expect(abs((c1.origin.x.value - left) - 92.5) <= 0.5, "child 1 at 92.5 (D1): \(c1.origin.x.value - left)")
    #expect(abs((c2.origin.x.value - left) - 93) <= 0.5, "child 2 at 93 (D1): \(c2.origin.x.value - left)")
}

/// **D1.** The label starts 12 from the group's leading edge (ink 12.5: the 12 point chevron slot plus the glyph's own
/// bearing) and the chevron sits at the leading edge, vertically centred in the 24 point row.
@Test @MainActor func theChevronIsAtTheLeadingEdgeAndTheLabelFollowsItsSlot() throws {
    let stage = try render(false)
    let left = stage.above.origin.x.value, top = stage.groupTop
    let all = stage.all.values
    let label = try #require(all.first { abs($0.origin.x.value - (left + 12)) < 0.5 && $0.size.height.value == 16
        && $0.size.width.value != 37 && $0.size.width.value != 36 && $0.size.width.value != 260 },
                             "the label is at +12")
    #expect(abs(label.origin.y.value - (top + 4)) <= 0.5, "centred in the 24 row: \(label.origin.y.value - top)")
    let chevron = try #require(all.first { $0.origin.x.value >= left && $0.origin.x.value < left + 4
        && $0.size.width.value <= 12 && $0.size.height.value <= 12 && $0.size.height.value > 0
        && $0.origin.y.value > top && $0.origin.y.value < top + 12 },
                               "a chevron at the leading edge")
    #expect(abs((chevron.origin.y.value + chevron.size.height.value / 2) - (top + 12)) <= 1, "vertically centred: \(chevron)")
}

/// **D1.** A nested group starts at its parent's x: the inner row is as wide as the outer, the inner label is at the same
/// +12, and the inner content is centred in the same 260 (the probe: outer to inner indentation 0).
@Test @MainActor func aNestedGroupStartsAtItsParentsX() throws {
    let root = stageTree {
        DisclosureGroup(isExpanded: .constant(true)) {
            DisclosureGroup(isExpanded: .constant(true)) { bar(27) } label: { Text("Inner") }
        } label: { Text("Outer") }
    }
    let stage = Stage(frame: try controlRender(root, width: 300, height: 200))
    // outer 24 + inner (24 + 16) = 64 (the probe: group 260 x 64).
    #expect(stage.groupHeight == 64, "outer row + inner row + one 16 child: \(stage.groupHeight)")
    let leaf = try #require(stage.all.values.first { $0.size.width.value == 27 })
    let left = stage.above.origin.x.value
    #expect(abs((leaf.origin.x.value - left) - 116.5) <= 0.5, "the leaf is centred in the 260: \(leaf.origin.x.value - left)")
    let rows = stage.all.values.filter { $0.size.width.value == 260 && $0.size.height.value == 24 }
    #expect(rows.count >= 2, "two 260 wide rows, the inner no narrower than the outer: \(rows.count)")
    #expect(rows.allSatisfy { $0.origin.x.value == left }, "both rows start at the parent's x (D1)")
}

/// **D2.** The title forms measure identically: a `LocalizedStringKey` literal, a `String` and a `Text` label.
@Test @MainActor func theTitleFormsMeasureIdentically() throws {
    func height(_ root: some Element) throws -> (Float, [Bounds<Pixels>]) {
        let stage = Stage(frame: try controlRender(root, width: 300, height: 200))
        return (stage.groupHeight, stage.all.values.sorted { "\($0)" < "\($1)" })
    }
    let title: String = "Section"
    let literal = try height(stageTree { DisclosureGroup("Section", isExpanded: .constant(false)) { bar(75) } })
    let string = try height(stageTree { DisclosureGroup(title, isExpanded: .constant(false)) { bar(75) } })
    let label = try height(stageTree { DisclosureGroup(isExpanded: .constant(false)) { bar(75) } label: { Text("Section") } })
    #expect(literal.0 == 24 && string.0 == 24 && label.0 == 24, "all 24 (D2): \(literal.0) \(string.0) \(label.0)")
    #expect(literal.1 == string.1 && string.1 == label.1, "the same frames in the same places")
    // The uncontrolled forms too.
    let bare = try height(stageTree { DisclosureGroup("Section") { bar(75) } })
    let bareString = try height(stageTree { DisclosureGroup(title) { bar(75) } })
    #expect(bare.1 == literal.1 && bareString.1 == literal.1, "an uncontrolled group measures as a controlled one")
}

/// **P-L3.** The chevron is swapped, not rotated: a different glyph box when collapsed (right) and expanded (down).
@Test @MainActor func theChevronIsAGlyphSwapNotARotation() throws {
    func chevron(_ open: Bool) throws -> Bounds<Pixels> {
        let stage = try render(open)
        let left = stage.above.origin.x.value, top = stage.groupTop
        // The glyph is the smallest box at the leading edge (its cell and slot wrap it).
        return try #require(stage.all.values.filter {
            $0.origin.x.value >= left && $0.origin.x.value < left + 4 && $0.size.width.value <= 12
                && $0.size.height.value > 0 && $0.size.height.value <= 12
                && $0.origin.y.value > top && $0.origin.y.value < top + 12
        }.min { $0.size.width.value * $0.size.height.value < $1.size.width.value * $1.size.height.value })
    }
    let right = try chevron(false), down = try chevron(true)
    #expect(right.size.width.value < right.size.height.value, "chevron.right is taller than wide: \(right)")
    #expect(down.size.width.value > down.size.height.value, "chevron.down is wider than tall: \(down)")
}

// MARK: - Content evaluation

/// **Content runs only while expanded**: 0 calls collapsed, over any number of frames; once expanded, once per frame.
/// Mutation: building `makeContent()` unconditionally reddens the first expectation.
@Test @MainActor func aCollapsedGroupNeverCallsItsContent() throws {
    let counter = Counter()
    func tree(_ open: Bool) -> some Element {
        stageTree {
            DisclosureGroup(isExpanded: .constant(open)) {
                let _ = counter.calls += 1
                bar(75)
            } label: { Text("Section") }
        }
    }
    for _ in 0..<3 { _ = try controlRender(tree(false), width: 300, height: 200) }
    #expect(counter.calls == 0, "collapsed: no call (\(counter.calls))")
    _ = try controlRender(tree(true), width: 300, height: 200)
    #expect(counter.calls == 1, "expanded: one call per frame (\(counter.calls))")
}

// MARK: - Input

/// A window over the stage with `group`; the group's header is clicked at its centre.
@MainActor private func window<G: ElementGroup>(@ElementBuilder _ group: @escaping () -> G) throws -> (Window, FakePlatformWindow) {
    try controlWindow { stageTree(group: group) }
}

@MainActor private func headerCentre(_ window: Window) throws -> Point<Pixels> {
    let stage = Stage(window: window)
    return Point(x: Pixels(stage.above.origin.x.value + 130), y: Pixels(stage.groupTop + 12))
}

@MainActor private func groupHeight(_ window: Window) -> Float { Stage(window: window).groupHeight }

/// **Uncontrolled.** A click on the label row expands, the state persists across frames, a second click collapses.
/// Mutation: a click that writes nothing; a state slot that is not at the group's identity (reset each frame).
@Test @MainActor func clickingTheHeaderTogglesUncontrolledStateAndItPersists() throws {
    let (window, platform) = try window {
        DisclosureGroup("Section") { bar(75); bar(74) }
    }
    #expect(groupHeight(window) == 24, "initially collapsed (D4)")
    controlClick(platform, at: try headerCentre(window))
    controlRedraw(window)
    #expect(groupHeight(window) == 56, "a click expands: \(groupHeight(window))")
    for _ in 0..<3 { controlRedraw(window) }
    #expect(groupHeight(window) == 56, "and the state persists across frames")
    controlClick(platform, at: try headerCentre(window))
    controlRedraw(window)
    #expect(groupHeight(window) == 24, "a second click collapses")
}

/// **Controlled.** The binding is read when building and written only by input: no write over many frames, one write per
/// click (the negation); a programmatic write re-renders without a further write.
/// Mutation: writing the binding from the build (e.g. the current value each frame) reddens the first expectation.
@Test @MainActor func aControlledBindingIsWrittenOnlyByTheClickAndAProgrammaticWriteRerenders() throws {
    let flag = Flag()
    let (window, platform) = try window {
        DisclosureGroup(isExpanded: flag.binding) { bar(75); bar(74) } label: { Text("Section") }
    }
    for _ in 0..<4 { controlRedraw(window) }
    #expect(flag.writes.isEmpty, "no write from building or painting: \(flag.writes)")
    controlClick(platform, at: try headerCentre(window))
    #expect(flag.writes == [true], "one click writes the negation once: \(flag.writes)")
    controlRedraw(window)
    #expect(groupHeight(window) == 56)
    flag.open = false   // programmatic
    controlRedraw(window)
    #expect(groupHeight(window) == 24, "a programmatic write re-renders")
    #expect(flag.writes == [true], "and is not written back: \(flag.writes)")
}

/// **Keyboard.** The label row is focusable and Space toggles (MetalUI's control convention, divergence 80's family).
@Test @MainActor func aFocusedHeaderTogglesOnSpace() throws {
    let flag = Flag()
    let (window, platform) = try window {
        DisclosureGroup(isExpanded: flag.binding) { bar(75) } label: { Text("Section") }
    }
    let tree = try controlTree(window, platform)
    let header = try #require(tree.nodes.first { $0.value.role == .disclosureTriangle }, "no disclosure triangle")
    #expect(platform.simulateAccessibilityRequest(.focus(header.key)))
    controlRedraw(window)
    platform.simulateInput(controlKey(" "))
    #expect(flag.writes == [true], "Space writes the negation: \(flag.writes)")
    platform.simulateInput(controlKey("a"))
    #expect(flag.writes == [true], "another key writes nothing")
}

/// **A disabled group refuses** a click, Space and an accessibility press. The control arm is the same fixture enabled,
/// which writes on each (so "refused" is not "never reachable").
@Test @MainActor func aDisabledGroupRefusesToToggle() throws {
    for disabled in [true, false] {
        let flag = Flag()
        let (window, platform) = try controlWindow {
            stageTree {
                DisclosureGroup(isExpanded: flag.binding) { bar(75) } label: { Text("Section") }
                    .disabled(disabled)
            }
        }
        controlClick(platform, at: try headerCentre(window))
        let tree = try controlTree(window, platform)
        let header = try #require(tree.nodes.first { $0.value.role == .disclosureTriangle })
        let pressed = platform.simulateAccessibilityRequest(.press(header.key))
        if disabled {
            #expect(flag.writes.isEmpty, "a click is refused: \(flag.writes)")
            #expect(!header.value.isEnabled && !header.value.actions.contains(.press), "a disabled node advertises no press")
            #expect(!pressed, "a press is refused")
        } else {
            #expect(flag.writes == [true, false], "control: enabled, the click and the press each write: \(flag.writes)")
            #expect(pressed && header.value.actions.contains(.press))
        }
    }
}

// MARK: - Accessibility (OG-F: MetalUI's choice, P-A3 unmeasured)

/// The label row publishes as a disclosure triangle, labelled by its text, valued `"0"` collapsed and `"1"` expanded, and
/// a press toggles it. Mutation: dropping the hint publishes a button; dropping the value leaves it nil.
@Test @MainActor func theHeaderIsADisclosureTriangleWithItsExpandedStateAndAPress() throws {
    let (window, platform) = try window {
        DisclosureGroup("Section") { bar(75) }
    }
    var tree = try controlTree(window, platform)
    var header = try #require(tree.nodes.first { $0.value.role == .disclosureTriangle }, "no disclosure triangle published")
    #expect(header.value.value == "0" && header.value.label == "Section", "collapsed, labelled: \(header.value)")
    #expect(header.value.actions.contains(.press) && header.value.isFocusable, "press and focus")
    #expect(platform.simulateAccessibilityRequest(.press(header.key)))
    tree = try controlTree(window, platform)
    header = try #require(tree.nodes.first { $0.value.role == .disclosureTriangle })
    #expect(header.value.value == "1", "a press expands it: \(header.value)")
    #expect(groupHeight(window) == 40, "24 + one 16 high child")
}

// MARK: - Animation (D3, OG-H)

private let linear12 = Animation.linear(duration: 1.2)

@MainActor private func widthAlphas(_ frame: Frame, _ w: Float) -> [Float] {
    frame.scene.rects.filter { $0.bounds.size.width == w }.map(\.background.a)
}

/// **D3a / D3b.** A bare binding write snaps (the content paints at alpha 1 at once, no animation in flight); the same write
/// under `withAnimation` animates the insertion through the default fade (`XF-H`: 0 at the start, 1/3 at 0.4 of the ramp,
/// landed at 1.3). Mutation: a group that gives the content no conditional unit (an always-present, zero-height branch) reads
/// 1 in both arms.
@Test @MainActor func aBareWriteSnapsAndAnAnimatedWriteFadesTheContentIn() throws {
    func tree(_ open: Bool) -> some Element {
        stageTree {
            DisclosureGroup(isExpanded: .constant(open)) { bar(75) } label: { Text("Section") }
        }
    }
    let bare = TransitionHarness()
    bare.frame(0, nil, tree(false))
    #expect(widthAlphas(bare.frame(0, nil, tree(true)), 75) == [1], "a bare write snaps")
    #expect(bare.store.transitions.liveCount == 0, "nothing in flight")

    let animated = TransitionHarness()
    animated.frame(0, nil, tree(false))
    let start = widthAlphas(animated.frame(0, linear12, tree(true)), 75)
    let third = widthAlphas(animated.frame(0.4, nil, tree(true)), 75)
    let done = widthAlphas(animated.frame(1.3, nil, tree(true)), 75)
    try #require(start.count == 1 && third.count == 1 && done.count == 1, "\(start) \(third) \(done)")
    #expect(abs(start[0] - 0) < 0.01 && abs(third[0] - 0.333) < 0.01 && done[0] == 1, "0 -> 0.33 -> 1: \(start) \(third) \(done)")
}
