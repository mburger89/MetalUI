import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// R3-10 item 4 (`LD-A`...`LD-H`, record 191, divergence 1045): right-to-left `layoutDirection` mirrors layout,
// through a real `Window` over the harness. Every figure is SwiftUI's, read by
// `docs/probes/swiftui-layout-direction.swift` (header holds the recorded output). The window is 100 x 40 and the
// content a 100 x 40 frame at its top leading corner, as the probe's arms are. Each test runs the left-to-right tree
// (the separating arm) beside the right-to-left one. Counts and frames, never time; the mutation each test is built
// to redden is in its doc comment and the full table is in record 191.

private func direction(_ rtl: Bool) -> LayoutDirection { rtl ? .rightToLeft : .leftToRight }

/// A 100 x 40 window over `content`, written under `rtl`'s direction outside a 100 x 40 top-leading frame.
@MainActor private func arm<C: ProposalElementGroup>(rtl: Bool, size: Size<Pixels> = sz(100, 40),
                                                _ content: @escaping @MainActor () -> C) throws -> TestWindow {
    try harnessWindow(size: size) {
        content()
            .frame(width: Pixels(100), height: Pixels(40), alignment: .topLeading)
            .environment(\.layoutDirection, direction(rtl))
    }
}

/// The x of the layout rect of each named element.
@MainActor private func layoutXs(_ window: TestWindow, _ ids: String...) throws -> [Float] {
    try ids.map { try window.frame(ofID: $0).origin.x.value }
}

/// The accessibility frame of an element declared with `.accessibilityIdentifier(id)`.
@MainActor private func axFrame(_ window: TestWindow, _ id: String) throws -> Bounds<Pixels> {
    try window.element(identifier: id).frame
}

// MARK: - Layout through the element tree

/// **LD-A.** An `HStack` of a 10 and a 20 wide leaf in a leading frame: 0/10, then 90/70 (probe A1), the frame's
/// leading edge on the right. Mutation (record 191): `Frame.environmentTop`'s `didSet` not setting
/// `tree.registersRightToLeft` reddens it and every test below that is right-to-left.
@Test @MainActor func aRightToLeftHStackIsMirroredThroughTheElementTree() throws {
    func positions(rtl: Bool) throws -> [Float] {
        let window = try arm(rtl: rtl) {
            HStack(spacing: Pixels(0)) {
                Color.red.frame(width: Pixels(10), height: Pixels(10)).id("a")
                Color.blue.frame(width: Pixels(20), height: Pixels(10)).id("b")
            }.frame(width: Pixels(100), alignment: .leading)
        }
        return try layoutXs(window, "a", "b")
    }
    #expect(try positions(rtl: false) == [0, 10])
    #expect(try positions(rtl: true) == [90, 70])
}

/// **LD-B.** The writer's scope ends: a sibling after a right-to-left subtree is left-to-right again, and a
/// left-to-right subtree nested in a right-to-left one keeps its own order inside its mirrored box (probe K1).
/// Mutation: the `didSet` setting the flag but never clearing it (a pop that leaves it set) reddens the sibling.
@Test @MainActor func aWritersScopeEndsAndANestedLeftToRightSubtreeKeepsItsOrder() throws {
    let window = try harnessWindow(size: sz(100, 80)) {
        VStack(spacing: Pixels(0)) {
            HStack(spacing: Pixels(0)) {
                Color.red.frame(width: Pixels(10), height: Pixels(10)).id("na")
                HStack(spacing: Pixels(0)) {
                    Color.red.frame(width: Pixels(10), height: Pixels(10)).id("ia")
                    Color.red.frame(width: Pixels(20), height: Pixels(10)).id("ib")
                }.environment(\.layoutDirection, .leftToRight)
                Color.red.frame(width: Pixels(10), height: Pixels(10)).id("nb")
            }
            .frame(width: Pixels(100), alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
            HStack(spacing: Pixels(0)) {
                Color.blue.frame(width: Pixels(10), height: Pixels(10)).id("after-a")
                Color.blue.frame(width: Pixels(20), height: Pixels(10)).id("after-b")
            }.frame(width: Pixels(100), alignment: .leading)
        }.frame(width: Pixels(100), height: Pixels(80), alignment: .topLeading)
    }
    #expect(try layoutXs(window, "na", "ia", "ib", "nb") == [90, 60, 70, 50])
    #expect(try layoutXs(window, "after-a", "after-b") == [0, 10], "a sibling after the scope is left-to-right")
}

/// **LD-A.** `padding(.leading, 10)` puts the pad on the right: the child at 80 (probe E1), and `.trailing` at 90 (E2);
/// a leading `frame` alignment moves to the right edge (B1). Mutation: the `.padding` arm of `placeNative` placing
/// its child unmirrored reddens the first row.
@Test @MainActor func aRightToLeftPaddingAndFrameAlignmentAreMirrored() throws {
    func x<C: ProposalElementGroup>(rtl: Bool, _ build: @escaping @MainActor () -> C) throws -> Float {
        try axFrame(try arm(rtl: rtl, build), "a").origin.x.value
    }
    let leadingPad = { @MainActor in
        HStack(spacing: Pixels(0)) {
            Color.red.frame(width: Pixels(10), height: Pixels(10)).accessibilityIdentifier("a").padding(.leading, Pixels(10))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #expect(try x(rtl: false, leadingPad) == 10)
    #expect(try x(rtl: true, leadingPad) == 80)
    let trailingPad = { @MainActor in
        HStack(spacing: Pixels(0)) {
            Color.red.frame(width: Pixels(10), height: Pixels(10)).accessibilityIdentifier("a").padding(.trailing, Pixels(10))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #expect(try x(rtl: false, trailingPad) == 0)
    #expect(try x(rtl: true, trailingPad) == 90)
    let leadingFrame = { @MainActor in
        HStack(spacing: Pixels(0)) {
            Color.red.frame(width: Pixels(10), height: Pixels(10)).accessibilityIdentifier("a")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #expect(try x(rtl: false, leadingFrame) == 0)
    #expect(try x(rtl: true, leadingFrame) == 90)
}

/// **LD-F.** Accessibility frames come from the placed rects, so they mirror with the layout: a 10 and a 20 wide
/// leaf in a right-to-left `HStack` are published at 90 and 70 (probe A1). Mutation: none needed beyond the
/// kernel's (the frames are derived), the test pins that nothing re-flips them.
@Test @MainActor func aRightToLeftAccessibilityFrameIsTheMirroredOne() throws {
    func frames(rtl: Bool) throws -> [Float] {
        let window = try arm(rtl: rtl) {
            HStack(spacing: Pixels(0)) {
                Color.red.frame(width: Pixels(10), height: Pixels(10)).accessibilityIdentifier("a")
                Color.blue.frame(width: Pixels(20), height: Pixels(10)).accessibilityIdentifier("b")
            }.frame(width: Pixels(100), alignment: .leading)
        }
        return try [axFrame(window, "a").origin.x.value, axFrame(window, "b").origin.x.value]
    }
    #expect(try frames(rtl: false) == [0, 10])
    #expect(try frames(rtl: true) == [90, 70])
}

// MARK: - Offset, hit testing and render effects

/// The 10 x 10 rect the scene paints, by its size (the only 10 x 10 one).
@MainActor private func leafX(_ window: TestWindow) throws -> Float {
    let found = window.scene.rects.filter { $0.bounds.size.width == 10 && $0.bounds.size.height == 10 }
    return try #require(found.first).bounds.origin.x
}

/// **LD-C** (probe F1/F2). `offset(x: 10)` written INSIDE the writer flips its sign: the leaf at 90 moves to 80;
/// written OUTSIDE the writer it does not: 90 + 10. Left-to-right is 10 both ways (the separating arm).
/// The window is 140 wide so the outside case stays inside it. Mutation: `affine(in:mirrored:)` called with
/// `mirrored: false` at the paint site reddens the first row (and the hit test below).
@Test @MainActor func anOffsetInsideTheWriterFlipsAndOutsideItDoesNot() throws {
    func leafX(rtl: Bool, insideOffset: Bool, outsideOffset: Bool) throws -> Float {
        let window = try harnessWindow(size: sz(140, 40)) {
            let inner = insideOffset
                ? Color.red.frame(width: Pixels(10), height: Pixels(10)).offset(x: Pixels(10))
                : Color.red.frame(width: Pixels(10), height: Pixels(10)).offset(x: Pixels(0))
            let written = inner
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(width: Pixels(100), height: Pixels(40), alignment: .topLeading)
                .environment(\.layoutDirection, direction(rtl))
            return written.offset(x: Pixels(outsideOffset ? 10 : 0))
        }
        return try MetalUITestingTests.leafX(window)
    }
    let origin = try leafX(rtl: false, insideOffset: false, outsideOffset: false)
    #expect(try leafX(rtl: true, insideOffset: false, outsideOffset: false) - origin == 90)
    #expect(try leafX(rtl: false, insideOffset: true, outsideOffset: false) - origin == 10)
    #expect(try leafX(rtl: true, insideOffset: true, outsideOffset: false) - origin == 80, "the leaf at 90 moved left by 10")
    #expect(try leafX(rtl: false, insideOffset: false, outsideOffset: true) - origin == 10)
    #expect(try leafX(rtl: true, insideOffset: false, outsideOffset: true) - origin == 100,
            "outside the writer the offset is not mirrored: 90 + 10")
}

/// **LD-C.** Hit testing follows the mirrored offset: a tappable 10 wide leaf at the leading edge under
/// `offset(x: 10)` sits at 10...20 left-to-right and at 80...90 right-to-left (90 - 10); a click at 85 hits in the
/// second and at 15 misses, and the first is the other way round. Mutation: the prepaint site's
/// `effect.affine(in:mirrored:)` called with `mirrored: false` reddens the right-to-left clicks.
@Test @MainActor func aClickFollowsAnOffsetInsideARightToLeftWriter() throws {
    final class Log { var taps = 0 }
    func taps(rtl: Bool, at x: Float) throws -> Int {
        let log = Log()
        let window = try arm(rtl: rtl) {
            Color.red.frame(width: Pixels(10), height: Pixels(10)).onTapGesture { log.taps += 1 }
                .offset(x: Pixels(10)).frame(maxWidth: .infinity, alignment: .leading)
        }
        window.click(at: pt(x, 5))
        return log.taps
    }
    #expect(try taps(rtl: false, at: 15) == 1 && taps(rtl: false, at: 85) == 0)
    #expect(try taps(rtl: true, at: 85) == 1)
    #expect(try taps(rtl: true, at: 15) == 0)
}

/// **LD-C** (probe P1). `scaleEffect(2, anchor: .leading)` scales about the leading edge, which is the right one:
/// a 20 wide leaf at 0 grows to 0...40 left-to-right and the one at 80...100 to 60...100 right-to-left.
/// Mutation: the anchor's x not replaced by `1 - x` in `mirroredSpec` reddens the right-to-left row.
@Test @MainActor func aScaleEffectAnchorsAtTheMirroredLeadingEdge() throws {
    func bounds(rtl: Bool) throws -> (Float, Float) {
        let window = try arm(rtl: rtl) {
            Color.red.frame(width: Pixels(20), height: Pixels(10)).scaleEffect(2, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        let found = try #require(window.scene.rects.first { $0.bounds.size.height == 20 })
        return (found.bounds.origin.x, found.bounds.size.width)
    }
    let leftToRight = try bounds(rtl: false), rightToLeft = try bounds(rtl: true)
    #expect(leftToRight.0 == 0 && leftToRight.1 == 40)
    #expect(rightToLeft.0 == 60 && rightToLeft.1 == 40)
}

// MARK: - Horizontal scrolling

/// A horizontal scroller over a 10 wide first leaf and a 290 wide filler: 300 of content in 100.
@MainActor private func scroller(rtl: Bool) throws -> TestWindow {
    try arm(rtl: rtl) {
        ProposalScrollView(.horizontal) {
            HStack(spacing: Pixels(0)) {
                Color.red.frame(width: Pixels(10), height: Pixels(10)).id("first")
                Color.blue.frame(width: Pixels(290), height: Pixels(20))
            }
        }
    }
}

/// The first leaf's painted x (the one 10 x 10 rect).
@MainActor private func firstX(_ window: TestWindow) throws -> Float { try leafX(window) }

/// **LD-E** (probe L1). A horizontal scroller opens at the leading edge: left-to-right the first leaf is at 0, right-to-left
/// at 90 (the content's right edge on the viewport's). Mutation: `ScrollChrome.translation(offset:)` ignoring
/// `mirrored` reddens the later rows; the kernel's `.scrollViewport` mirror reddens this one.
@Test @MainActor func aRightToLeftHorizontalScrollerOpensAtItsLeadingEdge() throws {
    #expect(try firstX(try scroller(rtl: false)) == 0)
    #expect(try firstX(try scroller(rtl: true)) == 90)
}

/// **LD-E.** The wheel's sign follows the logical offset. Left-to-right, fingers moving left (`-50`) scroll forward:
/// the first leaf goes to -50, and `+50` is clamped. Right-to-left it is the other way (the content opens at the right
/// edge): `+50` scrolls forward, the first leaf goes to 140, and `-50` is clamped at 90. The left-to-right rows are the
/// separating arm. Mutation: `Window.scroll` ignoring `scrollMirrored` (always `-= delta`) reddens the right-to-left rows.
@Test @MainActor func theWheelScrollsARightToLeftHorizontalScrollerTheOtherWay() throws {
    func after(rtl: Bool, delta: Float) throws -> Float {
        let window = try scroller(rtl: rtl)
        window.scroll(at: pt(50, 5), byDeltaX: delta, deltaY: 0)
        for _ in 0..<3 { window.tick() }
        return try firstX(window)
    }
    #expect(try after(rtl: false, delta: -50) == -50)
    #expect(try after(rtl: false, delta: 50) == 0)
    #expect(try after(rtl: true, delta: 50) == 140)
    #expect(try after(rtl: true, delta: -50) == 90)
}

/// **LD-E.** The overlay indicator starts at the leading (right) edge and travels left as the offset grows: the
/// 33.3 wide thumb of 100 / 300 is at 0 left-to-right and at 66.7 right-to-left after a 1-point scroll toward the
/// content's far end, and its travel is toward the other side. Mutation: `indicatorBounds` ignoring `mirrored`.
@Test @MainActor func theIndicatorOfARightToLeftScrollerStartsOnTheRight() throws {
    func thumbX(rtl: Bool, delta: Float) throws -> Float {
        let window = try scroller(rtl: rtl)
        window.scroll(at: pt(50, 5), byDeltaX: delta, deltaY: 0)
        window.tick()
        let thumb = try #require(window.scene.rects.first { $0.bounds.size.height == 3 })
        return thumb.bounds.origin.x
    }
    let leftToRight = try thumbX(rtl: false, delta: -1), rightToLeft = try thumbX(rtl: true, delta: 1)
    #expect(leftToRight < 5, "the thumb leaves the start by about a third of a point: \(leftToRight)")
    #expect(rightToLeft > 60, "the thumb sits against the right edge: \(rightToLeft)")
}

/// **LD-E.** `scrollTo` measures from the leading edge: a target at content offset 200 (a 10 wide leaf after 200 of
/// filler) is brought to the leading (right) edge, its right edge at 100 right-to-left and its left edge at 0
/// left-to-right. Mutation: `ScrollerFrame.logicalStart(of:)` ignoring `mirrored` (the right-to-left target lands
/// 200 away from the edge).
@Test @MainActor func scrollToBringsATargetToTheLeadingEdgeOfARightToLeftScroller() throws {
    @MainActor final class ProxyBox { var proxy: ScrollViewProxy? }
    func finalX(rtl: Bool) throws -> Float {
        let box = ProxyBox()
        let window = try arm(rtl: rtl) {
            ScrollViewReader { proxy in
                let _ = { box.proxy = proxy }()
                ProposalScrollView(.horizontal) {
                    HStack(spacing: Pixels(0)) {
                        Color.blue.frame(width: Pixels(200), height: Pixels(20))
                        Color.red.frame(width: Pixels(10), height: Pixels(10)).id("target")
                        Color.blue.frame(width: Pixels(90), height: Pixels(20))
                    }
                }
            }
        }
        window.tick()
        box.proxy?.scrollTo("target", anchor: .leading)
        for _ in 0..<4 { window.tick() }
        return try leafX(window)
    }
    #expect(try finalX(rtl: false) == 0)
    #expect(try finalX(rtl: true) == 90)
}

/// **LD-E.** A lazy horizontal stack in a right-to-left scroller realises the visible lines, and the same lines a
/// left-to-right one does at the mirrored offset. 1000 items 20 wide in 100: after the open frames both realise the
/// same count; a wheel of 1000 forward (`-1000` left-to-right, `+1000` right-to-left) realises the same items.
/// Mutation: `LazyLinePlanner.prepaint`'s `origin` read from `contentOrigin` instead of `logicalStart(of:)`.
@Test @MainActor func aLazyHStackInARightToLeftScrollerRealizesTheSameLinesAtTheMirroredOffset() throws {
    func realized(rtl: Bool, delta: Float) throws -> (count: Int, items: [String]) {
        let window = try arm(rtl: rtl) {
            ProposalScrollView(.horizontal) {
                LazyHStack(spacing: Pixels(0)) {
                    ForEach(0..<1000) { index in ProposalText("i\(index)").frame(width: Pixels(20)) }
                }
            }
        }
        window.tick(); window.tick()
        if delta != 0 {
            window.scroll(at: pt(50, 5), byDeltaX: delta, deltaY: 0)
            for _ in 0..<4 { window.tick() }
        }
        let items = try window.elements(role: .staticText).compactMap(\.value).sorted()
        return (window.lastFrameWork.lazyUnitsRealized, items)
    }
    let open = try (ltr: realized(rtl: false, delta: 0), rtl: realized(rtl: true, delta: 0))
    #expect(open.ltr.count > 0 && open.ltr.count == open.rtl.count)
    #expect(open.ltr.items == open.rtl.items)
    #expect(open.rtl.items.contains("i0"))
    let far = try (ltr: realized(rtl: false, delta: -1000), rtl: realized(rtl: true, delta: 1000))
    #expect(far.ltr.items == far.rtl.items)
    #expect(!far.rtl.items.contains("i0") && far.rtl.items.contains("i50"), "\(far.rtl.items)")
}

/// **LD-E (`SP-`).** `scrollPosition(id:)` reads the leading edge in logical extents: a lazy horizontal list of 20 wide items
/// scrolled forward by 300 (wheel `-300` left-to-right, `+300` right-to-left) writes item 15 either way, and writing 50 to the
/// binding brings item 50 to the leading edge (the cell at 0...20 left-to-right, at 80...100 right-to-left). Mutation:
/// `Frame.noteScrollTarget` measuring from `contentOrigin` (right-to-left writes a far item, here 0 or the last visible).
@Test @MainActor func scrollPositionReadsLogicalExtentsInARightToLeftScroller() throws {
    @MainActor final class IDBox { var id: Int? }
    func run(rtl: Bool) throws -> (written: Int?, atEdge: Bool) {
        let box = IDBox()
        let binding = Binding<Int?>(get: { box.id }, set: { box.id = $0 })
        let window = try arm(rtl: rtl) {
            ProposalScrollView(.horizontal) {
                LazyHStack(spacing: Pixels(0)) {
                    ForEach(0..<1000) { index in ProposalText("i\(index)").frame(width: Pixels(20)) }
                }.scrollTargetLayout()
            }.scrollPosition(id: binding)
        }
        window.tick(); window.tick()
        window.scroll(at: pt(50, 5), byDeltaX: rtl ? 300 : -300, deltaY: 0)
        for _ in 0..<4 { window.tick() }
        let written = box.id
        box.id = 50
        window.window.setNeedsRedraw()
        for _ in 0..<6 { window.tick() }
        let item = try window.element(label: "i50")
        // The text is narrower than its 20 wide cell and centred in it, so "at the edge" is "in the edge cell".
        let maxX = item.frame.origin.x.value + item.frame.size.width.value
        let atEdge = rtl ? (maxX > 80 && maxX <= 100) : (item.frame.origin.x.value >= 0 && item.frame.origin.x.value < 20)
        return (written, atEdge)
    }
    let leftToRight = try run(rtl: false), rightToLeft = try run(rtl: true)
    #expect(leftToRight.written == 15 && leftToRight.atEdge, "\(leftToRight)")
    #expect(rightToLeft.written == 15 && rightToLeft.atEdge, "\(rightToLeft)")
}

// MARK: - Not mirrored, on purpose

/// **Divergence 1045 pin** (wrong on purpose). A shape's own geometry is not mirrored: a `Shape` that covers only its left
/// 30 points (here a `contentShape`) is hit in 0...30 in a right-to-left environment, where SwiftUI fills (and hits) 70...100 (probe O1). The
/// layout around it is mirrored; the path is not. Flips when mirroring paths lands.
@Test @MainActor func aRightToLeftShapeIsNotYetMirrored() throws {
    struct LeftBar: Shape {
        func path(in rect: Bounds<Pixels>) -> Path {
            var path = Path()
            path.addRect(Bounds(origin: rect.origin, size: Size(width: Pixels(30), height: rect.size.height)))
            return path
        }
    }
    final class Log { var taps = 0 }
    func taps(rtl: Bool, at x: Float) throws -> Int {
        let log = Log()
        let window = try arm(rtl: rtl) {
            HStack(spacing: Pixels(0)) {
                Box().frame(width: Pixels(100), height: Pixels(40)).contentShape(LeftBar()).onClick { log.taps += 1 }
            }
        }
        window.click(at: pt(x, 20))
        return log.taps
    }
    #expect(try taps(rtl: false, at: 15) == 1 && taps(rtl: false, at: 85) == 0)
    #expect(try taps(rtl: true, at: 15) == 1, "not mirrored (divergence 1045): SwiftUI hits 85 here")
    #expect(try taps(rtl: true, at: 85) == 0)
}

// MARK: - Text

/// **LD-D** (probe M1-M3). `multilineTextAlignment` swaps `.leading` and `.trailing` under right-to-left and leaves
/// `.center`; glyphs themselves are not mirrored. A two-line text whose first line is the short one: its first line's
/// offset from the box's left edge (the longer line's left) is 0 for leading, positive for trailing and centre left-to-right;
/// right-to-left, leading reads as the left-to-right trailing figure and trailing as 0, centre unchanged. Mutation:
/// `TextAlignment.seam(in:)` returning `seam` for every direction reddens the right-to-left rows.
@Test @MainActor func multilineTextAlignmentSwapsLeadingAndTrailingUnderRightToLeft() throws {
    func firstLineOffset(rtl: Bool, _ alignment: TextAlignment) throws -> Float {
        let window = try harnessWindow(size: sz(100, 40)) {
            HStack(spacing: Pixels(0)) {
                ProposalText("Hi\nthere xxxxxx").frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: Pixels(100), height: Pixels(40), alignment: .topLeading)
            .environment(\.multilineTextAlignment, alignment)
            .environment(\.layoutDirection, direction(rtl))
        }
        let glyphs = window.scene.glyphs
        let top = try #require(glyphs.map(\.bounds.origin.y).min())
        let firstLine = glyphs.filter { $0.bounds.origin.y < top + 4 }
        let left = try #require(glyphs.map(\.bounds.origin.x).min())
        return try #require(firstLine.map(\.bounds.origin.x).min()) - left
    }
    let leading = try firstLineOffset(rtl: false, .leading)
    let trailing = try firstLineOffset(rtl: false, .trailing)
    let center = try firstLineOffset(rtl: false, .center)
    #expect(leading < 2 && trailing > 10 && center > 2 && center < trailing, "\(leading) \(center) \(trailing)")
    #expect(try abs(firstLineOffset(rtl: true, .leading) - trailing) < 2)
    #expect(try firstLineOffset(rtl: true, .trailing) < 2)
    #expect(try abs(firstLineOffset(rtl: true, .center) - center) < 2)
}

/// **LD-C/LD-F.** The text input area follows a mirrored offset: a focused `TextField` under `offset(x: 10)` moves its caret
/// rect by -10 right-to-left and +10 left-to-right, against the same field with no offset. Mutation: `effectBoundingBox`
/// reading `mirrored: false`.
@Test @MainActor func theCaretRectFollowsAnOffsetInsideARightToLeftWriter() throws {
    @MainActor final class Text { var value = "" }
    func caretX(rtl: Bool, offset: Float) throws -> Float {
        let model = Text()
        let window = try arm(rtl: rtl) {
            HStack(spacing: Pixels(0)) {
                TextField("", text: Binding(get: { model.value }, set: { model.value = $0 }))
                    .frame(width: Pixels(60), height: Pixels(20))
                    .offset(x: Pixels(offset))
            }
        }
        window.click(at: pt(rtl ? 70 + offset * -1 : 5 + offset, 10))
        window.tick()
        let area = try #require(window.platformWindow.textInputAreas.last ?? nil)
        return area.origin.x.value
    }
    #expect(try caretX(rtl: false, offset: 10) - caretX(rtl: false, offset: 0) == 10)
    #expect(try caretX(rtl: true, offset: 10) - caretX(rtl: true, offset: 0) == -10)
}
