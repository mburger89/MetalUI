import Foundation
import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI

// C10 lane 2: `ProgressView<Label, CurrentValueLabel>` — its sizes, values,
// labels, style, animation and accessibility (rulings `LK-E`, `LK-F`, `LK-P`,
// `LK-V`; spec `2026-10-08-controls-looks-design.md` §3.2, §4.2). SwiftUI's
// numbers are probe `docs/probes/swiftui-controls-looks.swift` arms `V0`–`V13`;
// text heights are MetalUI's own measured `Text` sizes (`controlTextSize`),
// never SwiftUI's points. Animation is driven by `simulateTick(timestamp:)` on a
// fake window; nothing sleeps.

// MARK: - Fixtures

/// One child measured at named proposals (`GreedyControlSizingTests`' harness).
private final class ProgressAnswers: @unchecked Sendable {
    var sizes: [String: SizeD] = [:]
}

private let progressProposals: [(String, ProposedSize)] = [
    ("ideal", ProposedSize(width: nil, height: nil)),
    ("infWidth", ProposedSize(width: .infinity, height: nil)),
    ("w200", ProposedSize(width: 200, height: nil)),
    ("w300", ProposedSize(width: 300, height: nil)),
]

private struct ProgressAsk: ProposalLayout {
    let answers: ProgressAnswers

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        for (name, offer) in progressProposals {
            answers.sizes[name] = subviews[0].sizeThatFits(offer).size
        }
        return subviews[0].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), proposal: proposal)
    }
}

/// `view`'s answers to the proposals above, the frame's report required empty.
@MainActor
private func answers<E: ElementGroup>(_ view: E) throws -> [String: SizeD] {
    let answers = ProgressAnswers()
    let frame = LayoutDifferential.render(width: 400, height: 300) {
        ProposalLayoutContainer(ProgressAsk(answers: answers)) { view }
    }
    try #require(frame.unlowerableFields.isEmpty, "the fixture reported \(frame.unlowerableFields)")
    try #require(answers.sizes.count == progressProposals.count, "measured \(answers.sizes.keys.sorted())")
    return answers.sizes
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.01 }

/// A caption-font text's rounded size.
@MainActor
private func captionSize(_ string: String) throws -> Size<Pixels> {
    let frame = try controlRender(controlRoot { Text(string).font(.caption) })
    // The text's own id: `.font` is a transparent scope (`controlTextSize`'s read).
    return try #require(frame.elementBounds[controlID([0, 0])], "no caption bounds").size
}

/// A ticking window over `content` (a `Row` root), bounds recorded, one frame
/// drawn at t = 0.
@MainActor
private func progressWindow<C: ElementGroup>(@ElementBuilder _ content: @escaping @MainActor () -> C) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        controlRoot(width: 400, height: 400) { content() }
    }
    window.recordsElementBounds = true
    platform.simulateTick(timestamp: 0)
    return (window, platform)
}

/// The 32×32 indicator's bounds in the last frame.
@MainActor
private func spinnerBounds(_ window: Window, side: Float = 32) throws -> Bounds<Pixels> {
    let boxes = window.lastElementBounds.filter { $0.value.size.width.value == side && $0.value.size.height.value == side }
    // The innermost: the box records the same bounds one level up.
    let leaves = boxes.filter { candidate in !boxes.contains { $0.key.parent == candidate.key } }
    try #require(leaves.count == 1, "one \(side)×\(side) indicator, found \(boxes.count)")
    return leaves.first!.value
}

/// Which of the 24 step angles (15° apart, clockwise from 12 o'clock) the
/// spinner's darkest spoke points at: the step the frame drew (`LK-F` item 1).
@MainActor
private func spinnerStep(_ window: Window) throws -> Int {
    let bounds = try spinnerBounds(window)
    let images = gxImages(window.lastScene)
    try #require(!images.isEmpty, "the spinner drew no image")
    let cx = Double(bounds.origin.x.value + bounds.size.width.value / 2)
    let cy = Double(bounds.origin.y.value + bounds.size.height.value / 2)
    let radius = Double(bounds.size.width.value) / 2 * 0.75
    var best = (step: -1, alpha: -1)
    for step in 0..<24 {
        let angle = Double(step) * 15 * Double.pi / 180
        let x = Int((cx + radius * sin(angle)).rounded(.down)), y = Int((cy - radius * cos(angle)).rounded(.down))
        let alpha = images.map { gxAlpha($0, x, y) }.max() ?? 0
        if alpha > best.alpha { best = (step, alpha) }
    }
    return best.step
}

// MARK: - Sizes (V0–V6)

/// **V0** (`LK-E` item 3). The spinner is 32×32 at every proposal, 16 at
/// `.small`, 10 at `.mini`, 32 at `.large`. Mutation: `.mini` = 12.
@Test @MainActor func theSpinnerIsThirtyTwoSixteenAndTenByControlSize() throws {
    let cases: [(ControlSize, Double)] = [(.regular, 32), (.small, 16), (.mini, 10), (.large, 32), (.extraLarge, 32)]
    for (size, side) in cases {
        let measured = try answers(ProgressView().controlSize(size))
        for (name, answer) in measured {
            #expect(answer == SizeD(width: side, height: side), "\(size) \(name): \(answer)")
        }
    }
}

/// **V3, V6** (`LK-E` item 3). A bar is 20 tall and greedy on the width: a
/// finite offer whole, infinity at an infinite one, 0 at `nil` — for a value,
/// a `nil` value (still a bar, `V6`) and `.linear` without one (`V2`).
/// Mutation: an ideal width of 30.
@Test @MainActor func theBarIsGreedyTwentyTallAndZeroWideAtNil() throws {
    let bars: [(String, [String: SizeD])] = [
        ("value 0.3", try answers(ProgressView(value: 0.3))),
        ("value nil", try answers(ProgressView(value: nil as Double?))),
        ("linear, no value", try answers(ProgressView().progressViewStyle(.linear))),
    ]
    for (name, measured) in bars {
        #expect(measured["ideal"] == SizeD(width: 0, height: 20), "\(name) ideal: \(measured["ideal"]!)")
        #expect(measured["w200"] == SizeD(width: 200, height: 20), "\(name) w200: \(measured["w200"]!)")
        #expect(measured["infWidth"] == SizeD(width: .infinity, height: 20), "\(name) ∞: \(measured["infWidth"]!)")
    }
}

/// **V3** (`LK-E` item 3). A bar is 12 tall at `.small` and `.mini`, 20 at
/// `.large`. Mutation: 20 at `.small`.
@Test @MainActor func aSmallBarIsTwelveTall() throws {
    for (size, height) in [(ControlSize.small, 12.0), (.mini, 12), (.large, 20)] {
        let measured = try answers(ProgressView(value: 0.3).controlSize(size))
        #expect(measured["w200"] == SizeD(width: 200, height: height), "\(size): \(measured["w200"]!)")
    }
}

/// **V4** (`LK-E` item 3). A titled bar is its title above the bar with no gap,
/// leading-aligned: `textH + 20` tall, the title's width at `nil`, the offer at
/// 300; the bar's top is the title's bottom. Mutation: gap 4.
@Test @MainActor func aTitledBarStacksTheTitleAboveWithNoGap() throws {
    let text = try controlTextSize("Loading")
    let measured = try answers(ProgressView("Loading", value: 0.3))
    // The answer is unrounded; the recorded text bounds are rounded (within 1).
    #expect(abs(measured["ideal"]!.width - Double(text.width.value)) < 1
                && measured["ideal"]!.height == Double(text.height.value) + 20,
            "ideal \(measured["ideal"]!) (text \(text))")
    #expect(measured["w300"] == SizeD(width: 300, height: Double(text.height.value) + 20), "w300 \(measured["w300"]!)")
    let frame = try controlRender(controlRoot { ProgressView("Loading", value: 0.3).frame(width: Pixels(300)) })
    let bar = try #require(frame.elementBounds.values.first { $0.size.width.value == 300 && $0.size.height.value == 20 })
    let title = try #require(frame.elementBounds.values.first { $0.size == text })
    #expect(title.origin.y.value + text.height.value == bar.origin.y.value && title.origin.x == bar.origin.x,
            "title \(title) above bar \(bar)")
}

/// **V4** (`LK-E` item 3). A current-value label sits below the bar in the
/// caption font, no gap: `textH("L") + 20 + captionH("30%")`. Mutation: the
/// body font.
@Test @MainActor func aCurrentValueLabelSitsBelowInTheCaptionFont() throws {
    let label = try controlTextSize("L"), caption = try captionSize("30%"), body = try controlTextSize("30%")
    try #require(caption.height != body.height, "the caption and body heights must differ, or this cannot fail")
    let measured = try answers(ProgressView(value: 0.3) { Text("L") } currentValueLabel: { Text("30%") })
    let height = Double(label.height.value) + 20 + Double(caption.height.value)
    #expect(measured["w300"] == SizeD(width: 300, height: height), "w300 \(measured["w300"]!), expected height \(height)")
}

/// **V1** (`LK-E` item 3). A titled spinner stacks the title below, centred,
/// 4 points apart: `max(32, textW) × (32 + 4 + textH)`. Mutation: the title
/// above.
@Test @MainActor func aTitledSpinnerStacksTheTitleBelowFourPointsApart() throws {
    let text = try controlTextSize("Loading")
    let measured = try answers(ProgressView("Loading"))
    #expect(abs(measured["ideal"]!.width - Double(max(32, text.width.value))) < 1
                && measured["ideal"]!.height == 36 + Double(text.height.value),
            "ideal \(measured["ideal"]!) (text \(text))")
    let frame = try controlRender(controlRoot { ProgressView("Loading") })
    let spinner = try #require(frame.elementBounds.values.first { $0.size.width.value == 32 && $0.size.height.value == 32 })
    let title = try #require(frame.elementBounds.values.first { $0.size == text })
    #expect(spinner.origin.y.value + 36 == title.origin.y.value, "spinner \(spinner) then title \(title)")
    #expect(abs((spinner.origin.x.value + 16) - (title.origin.x.value + text.width.value / 2)) < 0.5, "centred")
}

/// `LK-P` item 4. A titled bar in an `HStack(spacing: 20)` keeps its title
/// above its bar — one child of the stack, not two side by side. Mutation:
/// make the view a `Component` of two top-level nodes.
@Test @MainActor func aTitledProgressViewInAnHStackStacksItsTitleAbove() throws {
    let text = try controlTextSize("Loading")
    let frame = try controlRender(controlRoot {
        HStack(spacing: 20) { ProgressView("Loading", value: 0.3).frame(width: Pixels(100)) }
    })
    let bar = try #require(frame.elementBounds.values.first { $0.size.width.value == 100 && $0.size.height.value == 20 },
                           "no 100×20 bar")
    let title = try #require(frame.elementBounds.values.first { $0.size == text })
    #expect(title.origin.x == bar.origin.x && title.origin.y.value + text.height.value == bar.origin.y.value,
            "title \(title) above bar \(bar)")
}

// MARK: - Values (V8)

/// The one published node whose role is `role`, or `nil`.
@MainActor
private func progressNodes(_ tree: AccessibilityTree) -> [AccessibilityNode] {
    tree.nodes.values.filter { $0.role == .progressIndicator || $0.role == .busyIndicator }
}

/// **V8** (`LK-E` item 2). A negative value and a zero total are
/// indeterminate: a busy indicator, drawn as an indeterminate bar. Mutation:
/// clamp to 0 (a progress indicator valued 0).
@Test @MainActor func aNegativeValueOrAZeroTotalIsIndeterminate() throws {
    for (value, total) in [(-1.0, 1.0), (0, 0), (0.5, -2)] {
        let (window, platform) = try progressWindow { ProgressView(value: value, total: total) }
        let nodes = progressNodes(try controlTree(window, platform))
        try #require(nodes.count == 1, "one progress node for \(value)/\(total): \(nodes.map(\.role))")
        #expect(nodes[0].role == .busyIndicator && nodes[0].value == nil,
                "\(value)/\(total): \(nodes[0].role) \(nodes[0].value ?? "nil")")
    }
}

/// **V8** (`LK-E` items 2, 4). A value above the total draws full: the
/// accent fill is exactly the track's width (100), never wider. Mutation: no
/// clamp (the fill is 150 wide).
@Test @MainActor func aValueAboveTheTotalDrawsFull() throws {
    var root = controlRoot { ProgressView(value: 1.5, total: 1).frame(width: Pixels(100)) }
    let frame = Frame(contentSize: Size(width: controlPx(400), height: controlPx(200)), scaleFactor: 1)
    frame.render(&root)
    let bars = frame.finalizedScene().rects.filter { $0.bounds.size.height == 8 }
    try #require(bars.count == 2, "a track and a fill: \(bars.map(\.bounds))")
    #expect(bars.allSatisfy { $0.bounds.size.width == 100 }, "widths \(bars.map(\.bounds.size.width))")
}

/// `LK-E` item 2 (MetalUI's rule). A non-finite value or total is
/// indeterminate — never a trap — and nothing non-finite reaches a node.
/// Mutation: pass NaN through (the fraction reaches the fill and the AX value).
@Test @MainActor func aNonFiniteValueIsIndeterminateAndNothingNonFiniteIsStored() throws {
    for (value, total) in [(Double.nan, 1.0), (1, .nan), (.infinity, 1), (1, .infinity)] {
        let (window, platform) = try progressWindow { ProgressView(value: value, total: total).frame(width: Pixels(100)) }
        let nodes = progressNodes(try controlTree(window, platform))
        try #require(nodes.count == 1, "one progress node for \(value)/\(total)")
        #expect(nodes[0].role == .busyIndicator, "\(value)/\(total): \(nodes[0].role)")
        let finite = window.lastElementBounds.values.allSatisfy {
            $0.origin.x.value.isFinite && $0.origin.y.value.isFinite
                && $0.size.width.value.isFinite && $0.size.height.value.isFinite
        }
        #expect(finite, "every stored rect finite for \(value)/\(total)")
        #expect(window.lastScene.rects.allSatisfy { $0.bounds.size.width.isFinite && $0.bounds.origin.x.isFinite },
                "every drawn rect finite for \(value)/\(total)")
    }
}

// MARK: - Style (V2, V5)

/// **V2, V5** (`LK-E` item 2). `.circular` with a value draws a 32×32 ring
/// (not a bar), `.linear` without one an indeterminate bar (not the spinner).
/// Mutation: ignore the style.
@Test @MainActor func progressViewStyleCircularDrawsARingAndLinearAnIndeterminateBar() throws {
    let ring = try answers(ProgressView(value: 0.3).progressViewStyle(.circular))
    #expect(ring["w300"] == SizeD(width: 32, height: 32), "ring \(ring["w300"]!)")
    let bar = try answers(ProgressView().progressViewStyle(.linear))
    #expect(bar["w300"] == SizeD(width: 300, height: 20), "indeterminate bar \(bar["w300"]!)")
    // The ring publishes as a progress indicator with its fraction.
    let (window, platform) = try progressWindow { ProgressView(value: 0.25).progressViewStyle(.circular) }
    let nodes = progressNodes(try controlTree(window, platform))
    #expect(nodes.count == 1 && nodes.first?.role == .progressIndicator && nodes.first?.value == "0.25",
            "ring node \(nodes.map { "\($0.role) \($0.value ?? "nil")" })")
}

/// `LK-E` item 1 (`MD-B`'s precedent). The innermost style wins: a view's own
/// over its container's, a nearer container's over a farther one's. Mutation:
/// the outermost wins.
@Test @MainActor func theInnermostProgressViewStyleWins() throws {
    let own = try answers(VStack { ProgressView(value: 0.3).progressViewStyle(.linear) }.progressViewStyle(.circular))
    #expect(own["w300"] == SizeD(width: 300, height: 20), "the view's own .linear: \(own["w300"]!)")
    let nearer = try answers(VStack { VStack { ProgressView(value: 0.3) }.progressViewStyle(.circular) }
        .progressViewStyle(.linear))
    #expect(nearer["w300"] == SizeD(width: 32, height: 32), "the nearer container's .circular: \(nearer["w300"]!)")
}

// MARK: - Animation (V10, V13; LK-F)

/// **V13** (`LK-F` item 1). The spinner advances 24 discrete steps per 0.8 s
/// of the frame clock: step 0 at 0, 1 at 0.035, 12 at 0.4, 0 again at 0.8.
/// Mutation: 12 steps per 0.8 s.
@Test @MainActor func theSpinnerAdvancesTwentyFourStepsPerPointEightSeconds() throws {
    let (window, platform) = try progressWindow { ProgressView() }
    var steps: [Int] = []
    for time in [0.0, 0.035, 0.4, 0.8] {
        platform.simulateTick(timestamp: time)
        steps.append(try spinnerStep(window))
    }
    #expect(steps == [0, 1, 12, 0], "steps \(steps)")
}

/// `LK-F` item 3. An indeterminate view keeps the window animating; a
/// determinate one, a bar or a ring, does not. Mutation: always note.
@Test @MainActor func anIndeterminateViewKeepsTheWindowAnimatingAndADeterminateOneDoesNot() throws {
    let (spinner, spinnerPlatform) = try progressWindow { ProgressView() }
    spinnerPlatform.simulateTick(timestamp: 0.1)
    #expect(spinner.hasActiveAnimations, "the spinner animates")
    let (bar, barPlatform) = try progressWindow { ProgressView().progressViewStyle(.linear).frame(width: Pixels(100)) }
    barPlatform.simulateTick(timestamp: 0.1)
    #expect(bar.hasActiveAnimations, "the indeterminate bar animates")
    for determinate in [false, true] {
        let (window, platform) = try progressWindow {
            ProgressView(value: 0.5).progressViewStyle(determinate ? .circular : .automatic).frame(width: Pixels(100))
        }
        platform.simulateTick(timestamp: 0.1)
        #expect(!window.hasActiveAnimations, "a determinate \(determinate ? "ring" : "bar") does not animate")
    }
}

/// `LK-F` item 3 (the `GPUSurface` precedent). A hidden, transparent or
/// clipped-out spinner requests no frames. Mutation: note before the
/// visibility check.
@Test @MainActor func aHiddenOrZeroSizeSpinnerRequestsNoFrames() throws {
    let hidden = try progressWindow { ProgressView().hidden() }
    let transparent = try progressWindow { ProgressView().opacity(0) }
    let clipped = try progressWindow {
        Box { ProgressView() }.frame(width: Pixels(0), height: Pixels(0)).clipped()
    }
    for (name, (window, platform)) in [("hidden", hidden), ("transparent", transparent), ("clipped out", clipped)] {
        platform.simulateTick(timestamp: 0.1)
        #expect(!window.hasActiveAnimations, "a \(name) spinner keeps the window animating")
    }
    let (visible, platform) = try progressWindow { Box { ProgressView() }.frame(width: Pixels(40), height: Pixels(40)).clipped() }
    platform.simulateTick(timestamp: 0.1)
    #expect(visible.hasActiveAnimations, "the separating control: a visible clipped spinner animates")
}

/// **V10** (`LK-F` item 4). Reduce Motion does not stop the spinner: with it
/// on, the steps still advance and the window keeps animating. Mutation: gate
/// the step on `accessibilityReduceMotion`.
@Test @MainActor func reduceMotionDoesNotStopTheSpinner() throws {
    let (window, platform) = try progressWindow { ProgressView() }
    platform.simulateReduceMotionChange(to: true)
    platform.simulateTick(timestamp: 0.4)
    #expect(try spinnerStep(window) == 12, "the step under Reduce Motion")
    #expect(window.hasActiveAnimations, "still animating under Reduce Motion")
}

// MARK: - Accessibility (V7, V8; LK-G)

/// **V7, V8** (`LK-E` item 5). A determinate view publishes one
/// `.progressIndicator` valued with the fraction — 5/10 reads `0.5` — labelled
/// by its title, with no separate title text. Mutation: publish the raw value
/// (`5`).
@Test @MainActor func aDeterminateViewPublishesAProgressIndicatorWithTheFraction() throws {
    let (window, platform) = try progressWindow { ProgressView("Loading", value: 5, total: 10).frame(width: Pixels(100)) }
    let tree = try controlTree(window, platform)
    let nodes = progressNodes(tree)
    try #require(nodes.count == 1, "one progress node: \(tree.nodes.values.map(\.role))")
    #expect(nodes[0].role == .progressIndicator && nodes[0].value == "0.5" && nodes[0].label == "Loading",
            "\(nodes[0].role) value \(nodes[0].value ?? "nil") label \(nodes[0].label ?? "nil")")
    #expect(!tree.nodes.values.contains { $0.role == .staticText && ($0.value == "Loading" || $0.label == "Loading") },
            "the title is the indicator's label, not its own text")
}

/// **V7** (`LK-E` item 5). An indeterminate view publishes a `.busyIndicator`
/// with no value. Mutation: value `"0"`.
@Test @MainActor func anIndeterminateViewPublishesABusyIndicatorWithNoValue() throws {
    let (window, platform) = try progressWindow { ProgressView() }
    let nodes = progressNodes(try controlTree(window, platform))
    try #require(nodes.count == 1, "one progress node")
    #expect(nodes[0].role == .busyIndicator && nodes[0].value == nil, "\(nodes[0].role) \(nodes[0].value ?? "nil")")
}

// MARK: - Handler-carried modifiers, the hint strip, the sweep (lane 2 review)

/// `LK-P`, `LK-V`: a `ProgressView` takes the handler-carried `StyledElement`
/// modifiers as any control does. `.onClick` on a spinner runs on a click at its
/// centre; `.accessibilityLabel` labels the one published busy indicator (still
/// exactly one progress node). Two windows: a clickable element synthesizes a
/// button, and the progress hint names only a group's role (`publishedRole`),
/// so a clickable `ProgressView` publishes as a button — measured, not ruled
/// here. Mutation **V5**: `ProgressView.prepaint`'s `layout.body.handlers =
/// handlers` deleted (no click target; the label never reaches the node).
@Test @MainActor func aProgressViewTakesHandlerCarriedModifiersV5() throws {
    let model = ControlModel()
    let (clickable, clickPlatform) = try progressWindow { ProgressView().onClick { model.count += 1 } }
    let spinner = try spinnerBounds(clickable)
    let centre = Point(x: spinner.origin.x + spinner.size.width / 2, y: spinner.origin.y + spinner.size.height / 2)
    clickPlatform.simulateInput(.mouseDown(MouseEvent(position: centre)))
    clickPlatform.simulateInput(.mouseUp(MouseEvent(position: centre)))
    #expect(model.count == 1, "the click ran \(model.count) times")
    let (labelled, platform) = try progressWindow { ProgressView().accessibilityLabel("Syncing") }
    let nodes = progressNodes(try controlTree(labelled, platform))
    try #require(nodes.count == 1, "one progress node: \(nodes.map(\.role))")
    #expect(nodes[0].role == .busyIndicator && nodes[0].label == "Syncing",
            "\(nodes[0].role) label \(nodes[0].label ?? "nil")")
}

/// `LK-G`, `LK-V` item 6 (`AB-U`): the progress hint is stripped before the
/// declaration test, as `popoverHint` is — an untitled `ProgressView()` emits
/// no `axNodes` entry and writes no `$ax` slot, while its client record still
/// carries the busy hint. Mutation **V3**: `Frame.registerHandlers`'
/// `declaration.progressHint = nil` deleted (a declared node and a `$ax` slot).
@Test @MainActor func anUntitledProgressViewWritesNoAXSlotAndNoDeclaredNodeV3() throws {
    let table = StateTable()
    var root = controlRoot { ProgressView() }
    let frame = Frame(contentSize: Size(width: controlPx(400), height: controlPx(200)), scaleFactor: 1,
                      stateTable: table, collectsAccessibility: true)
    frame.render(&root)
    #expect(frame.axNodes.isEmpty, "declared nodes \(frame.axNodes.values.map(\.role))")
    #expect(!table.ids.contains { $0.component == .named(ElementID("$ax")) }, "a $ax slot was written")
    #expect(frame.axEmissions.contains { $0.declared.progressHint == .busy }, "the client record carries the busy hint")
}

/// `LK-F` item 2: the indeterminate bar's segment moves with the frame clock —
/// at t = 0 it sits at the track's start, at 0.4 s (a quarter of the 1.6 s
/// period) half way along its travel, both inside the 100-wide track (the
/// period and segment are a look, human check). Mutation **V6**:
/// `paintSweep`'s `travel` → `0.0` (the segment never moves).
@Test @MainActor func theIndeterminateBarSegmentMovesWithTheClockV6() throws {
    let (window, platform) = try progressWindow {
        ProgressView().progressViewStyle(.linear).frame(width: Pixels(100))
    }
    func segment() throws -> Float {
        let bars = window.lastScene.rects.filter { $0.bounds.size.height == 8 }
        try #require(bars.count == 2, "a track and a segment: \(bars.map(\.bounds))")
        let track = try #require(bars.first { $0.bounds.size.width == 100 }).bounds
        let accent = try #require(bars.first { $0.bounds.size.width == 30 }).bounds
        #expect(accent.origin.x >= track.origin.x && accent.origin.x + 30 <= track.origin.x + 100,
                "segment \(accent) outside track \(track)")
        return accent.origin.x - track.origin.x
    }
    platform.simulateTick(timestamp: 0)
    let start = try segment()
    platform.simulateTick(timestamp: 0.4)
    let quarter = try segment()
    #expect(start == 0 && quarter == 35, "segment offsets \(start), \(quarter)")
}
