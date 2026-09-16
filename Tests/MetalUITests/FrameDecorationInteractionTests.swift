import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
@testable import MetalUI

// The integration of plan tasks 4 and 5 (`feat/frame-sizing`,
// `feat/outer-modifiers`, merged 2026-09-16 on `integrate/tasks-4-5`):
// behaviour that exists only where the two tracks meet. The frame track gave
// the legacy `.frame(...)` SwiftUI's whole parameter surface and one lowering
// (`FrameLayer.swift`, `FR-C`); the outer-modifier track gave every
// `ModifiedElement` layer a `Decoration` that can be a SCOPE (`.opacity`,
// `.clipped()`), a border drawn after its content (`OM-V`), a focus ring
// (`OM-L`) and two prepaint-only hit-testing fields (`OM-J`, `OM-T`). Neither
// track's suite ever put one of those on a frame layer, because on each branch
// the other half did not exist. Each test below names the pair it covers and is
// recorded, with its mutations, in `docs/record/16-integration-tasks-4-5.md`.
//
// **This file imports `Metal`, so it must declare no `Dimension`-typed
// fixture** (`Fakes.swift`'s note on `AnimationTests.swift`).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func why(_ message: String) -> Comment { "\(message)" }

@MainActor
private final class ClickCounter {
    var count = 0
    func bump() { count += 1 }
}

@MainActor
private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor
private func hover(_ window: Window, _ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseMoved(MouseEvent(position: point)))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

@MainActor private func drawUntilClean(_ window: Window, limit: Int = 5) {
    for _ in 0..<limit where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// `Row { subject; 1x1 marker }.alignItems(.flexStart)`, the fixture shape
/// `DecorationPaintTests` and `OuterModifierMatrixTests` use. The `alignItems`
/// is load-bearing: `Row` centres on the cross axis (EP-8), so without it a
/// frame layer's y is the container's answer, not the frame's.
@MainActor
private func inRow<E: ElementGroup>(_ make: @escaping @MainActor () -> E) -> some Element {
    Row {
        make()
        Box().width(px(1)).height(px(1)).background(.scrim)
    }.alignItems(.flexStart)
}

/// Renders `make` in a fresh `side`x`side` fake window and returns it.
@MainActor
private func render<E: Element>(side: Int = 200, _ make: @escaping @MainActor () -> E) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: side, content: make)
    window.drawFrameIfNeeded()
    return (window, platform)
}

private func describe(_ b: MUIBounds) -> String {
    "[\(b.origin.x) \(b.origin.y) \(b.size.width)x\(b.size.height)]"
}

private func describe(_ r: MUIRect) -> String {
    let w = r.borderWidths
    return describe(r.bounds) + " bg(\(r.background.h),\(r.background.s),\(r.background.l),\(r.background.a))"
        + " border(\(w.top),\(w.right),\(w.bottom),\(w.left))"
        + " borderColor(\(r.borderColor.h),\(r.borderColor.s),\(r.borderColor.l),\(r.borderColor.a))"
        + " mask" + describe(r.contentMask)
}

/// A registered hit region, without its owning id (the shape
/// `OuterModifierMatrixTests` and `HitRegionTests` compare).
private func describe(_ h: Hitbox) -> String {
    let b = h.bounds
    return "[\(b.origin.x.value) \(b.origin.y.value) \(b.size.width.value)x\(b.size.height.value)]"
}

private func describe(_ b: Bounds<Pixels>) -> String {
    "[\(b.origin.x.value) \(b.origin.y.value) \(b.size.width.value)x\(b.size.height.value)]"
}

/// The one rect whose bounds are `w` x `h`, found by size so a marker or a
/// child can never be mistaken for the subject.
private func rect(_ scene: Scene, _ w: Float, _ h: Float) throws -> MUIRect {
    let matches = scene.rects.filter { $0.bounds.size.width == w && $0.bounds.size.height == h }
    try #require(matches.count == 1,
                 why("expected exactly one \(w)x\(h) rect, got \(matches.count): "
                     + scene.rects.map(describe).joined(separator: " | ")))
    return matches[0]
}

/// Whether `rect`'s BORDER was drawn in exactly `token`.
@MainActor
private func isBordered(_ rect: MUIRect, with token: ColorToken, in theme: Theme) -> Bool {
    let want = theme[token]
    return rect.borderColor.h == want.h && rect.borderColor.s == want.s
        && rect.borderColor.l == want.l && rect.borderColor.a > 0
}

/// Where each rect sits in the **finalized** paint order (`Scene.drawList`
/// restores a total order over rects and glyphs).
private func rectPaintPositions(_ scene: Scene) -> [Int] {
    var rects = [Int](repeating: -1, count: scene.rects.count)
    var next = 0
    for run in scene.drawList {
        for i in run.start..<(run.start + run.count) {
            if case .rect = run.kind { rects[i] = next }
            next += 1
        }
    }
    return rects
}

/// A two-member component whose members disagree in both dimensions (30x10
/// and 50x20), `OuterModifierMatrixTests`' `TwoMembers` shape.
private struct TwoMembers: Component {
    var content: some ElementGroup {
        Box().width(px(30)).height(px(10)).background(.accent)
        Box().width(px(50)).height(px(20)).background(.surface)
    }
}

// MARK: - 1. FR-N x OM-G / OM-V: a frame layer's clip and border bound the child it cannot shrink

/// **A `.clipped()` and a `.border` written after a legacy frame act on the
/// FRAME's box, so the cross-axis overflow `FR-N` leaves behind is cut and
/// outlined at 60x40, not at the child's 60x160.**
///
/// `FR-N` (frame track): a 200x160 child in a `.frame(width: 60, height: 40)`
/// is squeezed to 60 on the layer's main axis and overflows the cross axis —
/// under a `.flexStart` row it reads (0, −60) 60x160 (the same numbers the
/// track's test reads at y = 20 under a cross-centring `Row`). `OM-G`/`OM-V`
/// (outer-modifier track): `.clipped()` is a paint scope on the layer it is
/// written on and `.border` is emitted after that layer's content. On either
/// branch alone the pair could not be written: the frame had no decoration
/// scope, or the scope had no frame to sit on.
///
/// The control arm is the same chain without `.clipped()`: its child's mask is
/// the whole 200x200 surface, so the arms are `#require`d to disagree before
/// the clipped mask is believed. The border rect is then shown to be the
/// frame's 60x40 and to paint AFTER the overflowing child.
@Test @MainActor func aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink() throws {
    @MainActor func arm(clipped: Bool) throws -> (child: MUIRect, scene: Scene) {
        let (window, _) = try render {
            inRow {
                { () -> ModifiedElement<Box<EmptyGroup>> in
                    let chain = Box().width(px(200)).height(px(160)).background(.accent)
                        .frame(width: px(60), height: px(40))
                    return (clipped ? chain.clipped() : chain).border(.separator, width: px(2))
                }()
            }
        }
        let scene = window.lastScene
        return (try rect(scene, 60, 160), scene)
    }

    let plain = try arm(clipped: false)
    let clipped = try arm(clipped: true)

    // FR-N's geometry, re-read under this fixture: squeezed on the row axis,
    // overflowing the column axis, centred, so 60 tall of overflow above and
    // below a 40pt frame at y = 0.
    try #require(plain.child.bounds.origin.x == 0 && plain.child.bounds.origin.y == -60,
                 why("set up — FR-N's squeezed, overflowing child; got " + describe(plain.child)))
    try #require(describe(plain.child.contentMask) != describe(clipped.child.contentMask),
                 why("the two arms' masks must differ, or nothing here measures `.clipped()`: "
                     + describe(plain.child)))

    #expect(plain.child.contentMask.size.width == 200 && plain.child.contentMask.size.height == 200,
            why("unclipped, the overflow is masked by nothing but the surface; got "
                + describe(plain.child)))
    #expect(clipped.child.contentMask.origin.x == 0 && clipped.child.contentMask.origin.y == 0
                && clipped.child.contentMask.size.width == 60 && clipped.child.contentMask.size.height == 40,
            why("clipped, the mask is the FRAME layer's 60x40 box, not the child's 60x160; got "
                + describe(clipped.child)))

    // The border is the frame's box, drawn after the child (OM-V), in both arms.
    for (name, arm) in [("plain", plain), ("clipped", clipped)] {
        let border = try rect(arm.scene, 60, 40)
        #expect(isBordered(border, with: .separator, in: Theme.light)
                    && border.borderWidths.top == 2 && border.borderWidths.left == 2,
                why("\(name): the frame layer's 60x40 rect carries the border; got " + describe(border)))
        let positions = rectPaintPositions(arm.scene)
        let childIndex = try #require(arm.scene.rects.firstIndex { $0.bounds.size.height == 160 })
        let borderIndex = try #require(arm.scene.rects.firstIndex { $0.bounds.size.height == 40 })
        #expect(positions[borderIndex] > positions[childIndex],
                why("\(name): the border paints AFTER the overflowing child (OM-V); positions "
                    + "child \(positions[childIndex]), border \(positions[borderIndex])"))
    }
}

// MARK: - 2. FR-C x OM-J: contentShape on a frame layer insets the frame's box

/// **`.contentShape(inset:)` written after a frame insets the FRAME layer's hit
/// region; written before it, the child's** — and on the flexible overload the
/// region is the layer's clamped size, not the child's.
///
/// `OM-J` applies the inset in `Frame.registerHandlers` to the bounds of the
/// layer whose `Handlers` carry it; `FR-C` makes the frame one such layer.
/// Three arms against a control:
///
/// - after the fixed frame: `[10 10 40x20]` inside the 60x40 layer;
/// - before it (`.onClick.contentShape(inset: 5)` then `.frame`): the 20x20
///   child centred at (20, 10), so `[25 15 10x10]`;
/// - after the flexible frame `.frame(minWidth: 80, maxWidth: 100)` on a 20pt
///   child: the layer is 80 wide (`FR-E`: the minimum, never the proposal)
///   and 20 tall (no height bound), so an inset of 5 reads `[5 5 70x10]`.
///
/// Clicks confirm each region: the edge point (5, 20) hits the control and
/// misses the inset arm; (30, 20) hits both.
@Test @MainActor func aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox() throws {
    @MainActor func regions<E: ElementGroup>(_ make: @escaping @MainActor (ClickCounter) -> E)
        throws -> (regions: [String], counter: ClickCounter, platform: FakePlatformWindow, window: Window) {
        let counter = ClickCounter()
        let (window, platform) = try render { inRow { make(counter) } }
        return (window.lastHitboxes.map(describe), counter, platform, window)
    }

    let control = try regions { counter in
        Box().width(px(20)).height(px(20)).background(.surface)
            .frame(width: px(60), height: px(40))
            .onClick { counter.bump() }
    }
    let after = try regions { counter in
        Box().width(px(20)).height(px(20)).background(.surface)
            .frame(width: px(60), height: px(40))
            .contentShape(inset: px(10))
            .onClick { counter.bump() }
    }
    let before = try regions { counter in
        Box().width(px(20)).height(px(20)).background(.surface)
            .onClick { counter.bump() }
            .contentShape(inset: px(5))
            .frame(width: px(60), height: px(40))
    }
    let flexible = try regions { counter in
        Box().width(px(20)).height(px(20)).background(.surface)
            .frame(minWidth: px(80), maxWidth: px(100))
            .contentShape(inset: px(5))
            .onClick { counter.bump() }
    }

    try #require(control.regions != after.regions,
                 why("the control and the inset arm must register different regions: "
                     + "\(control.regions) vs \(after.regions)"))
    #expect(control.regions == ["[0.0 0.0 60.0x40.0]"],
            why("the control registers the frame layer's whole box: \(control.regions)"))
    #expect(after.regions == ["[10.0 10.0 40.0x20.0]"],
            why("an inset written after the frame insets the FRAME's box: \(after.regions)"))
    #expect(before.regions == ["[25.0 15.0 10.0x10.0]"],
            why("an inset written before the frame insets the CHILD's box, centred in the frame: "
                + "\(before.regions)"))
    #expect(flexible.regions == ["[5.0 5.0 70.0x10.0]"],
            why("on the flexible frame the region is the layer's clamped 80x20 less the inset: "
                + "\(flexible.regions)"))

    click(control.platform, at: pt(5, 20))
    click(after.platform, at: pt(5, 20))
    #expect(control.counter.count == 1, "the edge point hits the control")
    #expect(after.counter.count == 0, "and misses the inset frame layer")
    click(after.platform, at: pt(30, 20))
    #expect(after.counter.count == 1, "while the centre still hits it")
    click(before.platform, at: pt(22, 20))
    #expect(before.counter.count == 0, "inside the frame but outside the child's inset box: a miss")
    click(before.platform, at: pt(30, 20))
    #expect(before.counter.count == 1, "the child's centre hits")
}

// MARK: - 3. FR-C x OM-L: the focus ring and hover border draw on the layer they are written on

/// **A focus ring, a hover border and a plain border written after a legacy
/// frame draw at the frame layer's box; written before it, at the child's.**
///
/// `OM-L`'s `focus ?? hover ?? plain` selector runs per decoration-painting
/// site, and a `ModifiedElement` paints each layer (`MC-I`); `FR-C`'s frame is
/// a layer with a default `Decoration`, so the ring lands wherever the
/// `.focusBorder` was written. The two orders are `#require`d to disagree in
/// two ways: the bordered rect's size (60x40 against 20x20) and the hover
/// answer at (5, 5) — inside the frame's box but outside the child's, so the
/// after-order reads the hover border and the before-order the plain one,
/// because only the layer carrying the `onClick` has a hitbox to hover.
@Test @MainActor func aFocusRingAndHoverBorderDrawOnTheLayerTheyAreWrittenOnAroundAFrame() throws {
    @MainActor func check(_ name: String, size: (Float, Float), origin: (Float, Float),
                          hoveredAtCornerReads: ColorToken,
                          _ make: @escaping @MainActor () -> some ElementGroup) throws {
        let (window, platform) = try render { inRow { make() } }
        let theme = window.theme
        @MainActor func bordered(_ state: String) throws -> MUIRect {
            let all = window.lastScene.rects.map(describe).joined(separator: " | ")
            let r = try #require(window.lastScene.rects.first { $0.borderColor.a > 0 },
                                 why("\(name), \(state): nothing painted a border: " + all))
            #expect(r.bounds.size.width == size.0 && r.bounds.size.height == size.1
                        && r.bounds.origin.x == origin.0 && r.bounds.origin.y == origin.1,
                    why("\(name), \(state): the border sits on the layer it was written on; got "
                        + describe(r)))
            return r
        }
        #expect(isBordered(try bordered("plain"), with: .surface, in: theme))

        let hitboxes = window.lastHitboxes
        try #require(hitboxes.count == 1, why("\(name): one hitbox, got \(hitboxes.count)"))
        window.focus(hitboxes[0].id)
        window.drawFrameIfNeeded()
        #expect(isBordered(try bordered("focused"), with: .separator, in: theme),
                why("\(name): the FOCUS RING draws at the layer's box"))

        window.focus(nil)
        hover(window, platform, at: pt(5, 5))
        #expect(isBordered(try bordered("hovered at (5, 5)"), with: hoveredAtCornerReads, in: theme),
                why("\(name): the corner of the frame is \(hoveredAtCornerReads == .accent ? "inside" : "outside")"
                    + " the hitbox that carries the hover"))
    }

    try check("after the frame", size: (60, 40), origin: (0, 0), hoveredAtCornerReads: .accent) {
        Box().width(px(20)).height(px(20)).background(.surface)
            .frame(width: px(60), height: px(40))
            .border(.surface, width: px(2)).hoverBorder(.accent, width: px(2))
            .focusBorder(.separator, width: px(2))
            .focusable().onClick {}
    }
    try check("before the frame", size: (20, 20), origin: (20, 10), hoveredAtCornerReads: .surface) {
        Box().width(px(20)).height(px(20)).background(.surface)
            .border(.surface, width: px(2)).hoverBorder(.accent, width: px(2))
            .focusBorder(.separator, width: px(2))
            .focusable().onClick {}
            .frame(width: px(60), height: px(40))
    }
}

// MARK: - 4. CO-U side door x OM-N / OM-G: a component's frame carries the new decorations

/// **`anyComponent.frame(...)` is the side door through which a `Component`
/// reaches every `StyledElement` decoration, and the new scopes reach its
/// members through it**: `.opacity` fades both members' fills, `.clipped()`
/// masks them to the frame's box, `.border` outlines the frame, and none of
/// it distributes — the members keep their own 30x10 and 50x20.
///
/// CLAUDE.md records the door "by reading only"; this is its first
/// measurement. The frame track pinned that the frame WRAPS a component's body
/// (`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`); the
/// outer-modifier track pinned each scope on a `Box`. A component's `padding`
/// now wraps per member (`OM-D`), so the third arm puts one under the frame
/// and reads two more nodes and the same fade — the per-member wrappers sit
/// inside the frame's scope.
@Test @MainActor func aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers() throws {
    @MainActor func nodeCount<E: ElementGroup>(_ make: @escaping @MainActor () -> E) -> Int {
        var root = inRow(make)
        let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1)
        frame.render(&root)
        return frame.tree.nodeCount
    }
    @MainActor func members(_ scene: Scene) throws -> (a: MUIRect, b: MUIRect) {
        (try rect(scene, 30, 10), try rect(scene, 50, 20))
    }

    let bare = nodeCount { TwoMembers() }
    let framed = nodeCount {
        TwoMembers().frame(width: px(100), height: px(40)).opacity(0.5)
            .border(.separator, width: px(2)).clipped()
    }
    let padded = nodeCount {
        TwoMembers().padding(px(4)).frame(width: px(100), height: px(40)).opacity(0.5)
    }
    #expect(framed == bare + 1, "the frame is ONE node around the body, not one per member; \(framed) vs \(bare)")
    #expect(padded == bare + 3, "a per-member padding (OM-D) under the frame: two wrappers and one frame; \(padded) vs \(bare)")

    let (control, _) = try render { inRow { TwoMembers().frame(width: px(100), height: px(40)) } }
    let (decorated, _) = try render {
        inRow {
            TwoMembers().frame(width: px(100), height: px(40)).opacity(0.5)
                .border(.separator, width: px(2)).clipped()
        }
    }
    let (paddedWindow, _) = try render {
        inRow { TwoMembers().padding(px(4)).frame(width: px(100), height: px(40)).opacity(0.5) }
    }

    let plain = try members(control.lastScene)
    let faded = try members(decorated.lastScene)
    let paddedMembers = try members(paddedWindow.lastScene)
    try #require(plain.a.background.a == 1 && plain.b.background.a == 1,
                 why("set up — the control's members are opaque: " + describe(plain.a) + " " + describe(plain.b)))
    try #require(plain.a.contentMask.size.width == 200,
                 why("set up — the control's members are masked by the surface only: " + describe(plain.a)))

    #expect(faded.a.background.a == 0.5 && faded.b.background.a == 0.5,
            why("the frame's opacity fades BOTH members: " + describe(faded.a) + " " + describe(faded.b)))
    #expect(faded.a.contentMask.size.width == 100 && faded.a.contentMask.size.height == 40
                && faded.b.contentMask.size.width == 100 && faded.b.contentMask.size.height == 40,
            why("the frame's clip masks both members to its 100x40: " + describe(faded.a) + " " + describe(faded.b)))
    let border = try rect(decorated.lastScene, 100, 40)
    #expect(isBordered(border, with: .separator, in: decorated.theme),
            why("the frame's rect carries the border: " + describe(border)))
    #expect(paddedMembers.a.background.a == 0.5 && paddedMembers.b.background.a == 0.5,
            why("the per-member padding wrappers sit inside the frame's opacity scope: "
                + describe(paddedMembers.a) + " " + describe(paddedMembers.b)))
    // The members' own sizes were found by size above, so the frame did not
    // distribute; their positions show the body centred as a unit in the frame
    // (the frame track's numbers, one level up).
    #expect(plain.a.bounds.origin.x == 10 && plain.b.bounds.origin.x == 40,
            why("the body is centred as a unit: a at 10, b at 40; got " + describe(plain.a) + " " + describe(plain.b)))
}

// MARK: - 5. FR-C x OM-J x AB-E: accessibility reads the frame's box, hit testing the inset

/// **A labelled click target on a frame layer publishes the FRAME's 60x40 as
/// its accessibility frame while its hit region is the inset 40x20** — and a
/// press through the bridge still runs the handler, because the press goes
/// through the hitboxes, which exist.
///
/// `AB-E`: `accessibilityFrame` is the unclipped element frame; `OM-J`: the
/// content shape reaches the hitbox alone (pinned on a `Box` by
/// `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration`);
/// `FR-C`: the frame is a layer whose `Handlers` carry both the label and the
/// inset when they are written after it. The disagreeing arm writes the label
/// and the click BEFORE the frame, so the published frame is the child's
/// 20x20 at (20, 10) — the two arms' frames are `#require`d apart.
///
/// **The `Window` is returned and held, not only its platform.** The first
/// draft of this test dropped it and the press read `false` for a reason that
/// had nothing to do with either track: `Window` owns the request path, and a
/// deallocated one answers nothing (`HitRegionTests` records the same trap for
/// clicks).
@Test @MainActor func aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset() throws {
    @MainActor func publish<E: ElementGroup>(_ name: String, _ make: @escaping @MainActor (ClickCounter) -> E) throws
        -> (frame: Bounds<Pixels>, regions: [String], counter: ClickCounter,
            id: AccessibilityNodeID, node: AccessibilityNode, platform: FakePlatformWindow, window: Window) {
        let counter = ClickCounter()
        let (window, platform) = try render { inRow { make(counter) } }
        platform.simulateAccessibilityRequest(.activate)
        drawUntilClean(window)
        let tree = try #require(platform.publishedAccessibilityTrees.last, "\(name): nothing published")
        let labelled = tree.nodes.filter { $0.value.label == "go" }
        try #require(labelled.count == 1, "\(name): one node labelled go, read \(labelled.count)")
        let (id, node) = labelled[labelled.startIndex]
        let geometry = try #require(tree.geometry[id], "\(name): no geometry for the labelled node")
        return (geometry.frame, window.lastHitboxes.map(describe), counter, id, node, platform, window)
    }

    let after = try publish("label after the frame") { counter in
        Box().width(px(20)).height(px(20)).background(.surface)
            .frame(width: px(60), height: px(40))
            .contentShape(inset: px(10))
            .onClick { counter.bump() }
            .accessibilityLabel("go")
    }
    let before = try publish("label before the frame") { counter in
        Box().width(px(20)).height(px(20)).background(.surface)
            .onClick { counter.bump() }
            .accessibilityLabel("go")
            .frame(width: px(60), height: px(40))
    }

    try #require(describe(after.frame) != describe(before.frame),
                 why("the two orders must publish different frames: "
                     + describe(after.frame) + " vs " + describe(before.frame)))
    #expect(describe(after.frame) == "[0.0 0.0 60.0x40.0]",
            why("the frame layer's whole box is the accessibility frame: " + describe(after.frame)))
    #expect(after.regions == ["[10.0 10.0 40.0x20.0]"],
            why("while the hit region is the inset one: \(after.regions)"))
    #expect(after.node.role == .button && after.node.actions == [.press],
            why("a click target on a frame layer is a pressable button: \(after.node)"))
    let pressed = after.platform.simulateAccessibilityRequest(.press(after.id))
    #expect(pressed, why("the press is accepted: node \(after.id) against hitboxes "
                         + "\(after.window.lastHitboxes.map { "\($0.id) click=\($0.handlers.onClick != nil)" })"))
    #expect(after.counter.count == 1, "and runs the handler through the (inset) hitbox; ran \(after.counter.count)")

    #expect(describe(before.frame) == "[20.0 10.0 20.0x20.0]",
            why("written before the frame, the label sits on the child, centred in the frame: "
                + describe(before.frame)))
    #expect(before.regions == ["[20.0 10.0 20.0x20.0]"],
            why("and so does the click: \(before.regions)"))
}

// MARK: - 6. EV-D x FR-C x OM-L: a disabled scope around a framed focus ring

/// **`.disabled(true)` around a framed, focusable, bordered click target
/// suppresses its focus ring, its hover border and its click; written before
/// the frame, the scope sits inside and the frame layer's handlers stay live**
/// (`EV-X`).
///
/// `EV-D`'s gate lives in `Frame.registerHandlers`, which every layer reaches
/// through `registerAndScope`; `OM-L`'s ring reads the resolved focus and
/// `PaintPass.isHovered`, both of which are empty for an element that
/// registered nothing. Three arms: the enabled control (ring, hover border and
/// a counted click), the disabled one (none of the three, and no hitbox), and
/// the `EV-X` order (`.disabled(true)` on the child, `.frame` and the handlers
/// after it) which reads exactly as the control.
@Test @MainActor func aDisabledScopeAroundAFramedFocusRingSuppressesRingHoverAndClick() throws {
    struct Reading: Equatable {
        var hitboxes: Int
        var focusedBorder: ColorToken?
        var hoveredBorder: ColorToken?
        var clicks: Int
    }
    @MainActor func read<E: ElementGroup>(_ name: String, _ make: @escaping @MainActor (ClickCounter) -> E) throws -> Reading {
        let counter = ClickCounter()
        let (window, platform) = try render { inRow { make(counter) } }
        let theme = window.theme
        @MainActor func borderToken() -> ColorToken? {
            guard let r = window.lastScene.rects.first(where: { $0.borderColor.a > 0 }) else { return nil }
            for token in [ColorToken.surface, .accent, .separator] where isBordered(r, with: token, in: theme) {
                return token
            }
            return nil
        }
        let hitboxes = window.lastHitboxes.count
        // The same structural id in every arm: the frame layer is the row's
        // `positional(0)` child, and an `EnvironmentScope` adds no id level, so
        // the disabled arm asks for exactly the focus the enabled one gets.
        // Spelled rather than taken from a hitbox, because the disabled arm has
        // none; the control checks the spelling against its own.
        let rowID = GlobalElementID.child(of: nil, at: 0, name: nil)
        let id = GlobalElementID.child(of: rowID, at: 0, name: nil)
        if hitboxes == 1 {
            try #require(window.lastHitboxes[0].id == id,
                         why("\(name): the spelled id is the frame layer's; hitbox id \(window.lastHitboxes[0].id)"))
        }
        window.focus(id)
        window.drawFrameIfNeeded()
        let focused = borderToken()
        window.focus(nil)
        hover(window, platform, at: pt(5, 5))
        let hovered = borderToken()
        click(platform, at: pt(30, 20))
        return Reading(hitboxes: hitboxes, focusedBorder: focused, hoveredBorder: hovered, clicks: counter.count)
    }

    let control = try read("enabled") { counter in
        Box().width(px(20)).height(px(20)).background(.surface)
            .frame(width: px(60), height: px(40))
            .border(.surface, width: px(2)).hoverBorder(.accent, width: px(2))
            .focusBorder(.separator, width: px(2))
            .focusable().onClick { counter.bump() }
            .disabled(false)
    }
    let disabled = try read("disabled") { counter in
        Box().width(px(20)).height(px(20)).background(.surface)
            .frame(width: px(60), height: px(40))
            .border(.surface, width: px(2)).hoverBorder(.accent, width: px(2))
            .focusBorder(.separator, width: px(2))
            .focusable().onClick { counter.bump() }
            .disabled(true)
    }
    let scopeInside = try read("scope written before the frame") { counter in
        Box().width(px(20)).height(px(20)).background(.surface)
            .disabled(true)
            .frame(width: px(60), height: px(40))
            .border(.surface, width: px(2)).hoverBorder(.accent, width: px(2))
            .focusBorder(.separator, width: px(2))
            .focusable().onClick { counter.bump() }
    }

    try #require(control == Reading(hitboxes: 1, focusedBorder: .separator, hoveredBorder: .accent, clicks: 1),
                 why("set up — the enabled control focuses, hovers and clicks: \(control)"))
    #expect(disabled == Reading(hitboxes: 0, focusedBorder: .surface, hoveredBorder: .surface, clicks: 0),
            why("disabled: no hitbox, the plain border under focus and hover, no click; got \(disabled)"))
    #expect(scopeInside == control,
            why("a scope written BEFORE the frame sits inside it (EV-X): the frame layer's handlers are live; got \(scopeInside)"))
}

// MARK: - 7. OM-J x MC-A: a content shape across a wrapping layer

/// **`.contentShape(inset:)` written BEFORE a wrapping modifier, with the
/// `onClick` written after it, is inert: the inset lands on the inner layer,
/// whose `Handlers` carry no click, so the outer layer registers its whole
/// frame. Written after the wrapper it insets the wrapper's box.** SwiftUI
/// honours both orders.
///
/// Probe `docs/probes/swiftui-content-shape-hit-region.swift`, arms S0–S3
/// (added by this integration step, 2026-09-16, positive control S3 reads edge
/// 1): a 120x120 colour padded by 40 in a 200x200 window, clicked at the
/// centre (100, 100), in the colour's outer band (50, 100) and in the padding
/// (10, 100).
///
/// - S1 `colour.contentShape(inset 20).padding(40).tap` reads 1 / 0 / 0 in
///   SwiftUI; MetalUI reads 1 / 1 / 1. **Pinned wrong on purpose** — a
///   divergence (lane 3's verifier measured it; the outer-modifier track
///   carried it unprobed). It is `OM-I` and `OM-AL`'s mechanism: the default
///   region is the frame, and a per-layer field does not reach a click on a
///   layer written after it.
/// - S2 `colour.padding(40).contentShape(inset 20).tap` reads 1 / 1 / 0 in
///   both. Agreement.
///
/// The two orders are `#require`d to register different regions before
/// either is believed.
@Test @MainActor func aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt() throws {
    @MainActor func arm<E: Element>(_ make: @escaping @MainActor (ClickCounter) -> E)
        throws -> (regions: [String], clicks: [Int]) {
        var clicks: [Int] = []
        var regions: [String] = []
        for point in [pt(100, 100), pt(50, 100), pt(10, 100)] {
            let counter = ClickCounter()
            let (window, platform) = try render { make(counter) }
            regions = window.lastHitboxes.map(describe)
            click(platform, at: point)
            clicks.append(counter.count)
            withExtendedLifetime(window) {}
        }
        return (regions, clicks)
    }

    let insetBefore = try arm { counter in
        Box().width(px(120)).height(px(120)).background(.surface)
            .contentShape(inset: px(20))
            .padding(px(40))
            .onClick { counter.bump() }
    }
    let insetAfter = try arm { counter in
        Box().width(px(120)).height(px(120)).background(.surface)
            .padding(px(40))
            .contentShape(inset: px(20))
            .onClick { counter.bump() }
    }

    try #require(insetBefore.regions != insetAfter.regions,
                 why("the two orders must register different regions: "
                     + "\(insetBefore.regions) vs \(insetAfter.regions)"))
    #expect(insetAfter.regions == ["[20.0 20.0 160.0x160.0]"],
            why("written after the padding, the inset insets the padded box: \(insetAfter.regions)"))
    #expect(insetAfter.clicks == [1, 1, 0],
            why("S2: SwiftUI reads centre 1, band 1, edge 0; got \(insetAfter.clicks)"))
    // Pinned wrong on purpose: SwiftUI's S1 reads [1, 0, 0].
    #expect(insetBefore.regions == ["[0.0 0.0 200.0x200.0]"],
            why("written before the padding, the inset is inert and the padded layer registers "
                + "its whole frame: \(insetBefore.regions)"))
    #expect(insetBefore.clicks == [1, 1, 1],
            why("S1 diverges: SwiftUI reads [1, 0, 0]; MetalUI hits everywhere; got \(insetBefore.clicks)"))
}

// MARK: - 8. FR-C x OM-C: the frame/background and padding/frame/background orders

/// **A `.background` written after a legacy frame fills the frame's 60x60; written
/// before it, the 20x20 child's — and a padding layer between them changes
/// neither answer.** Probe `docs/probes/swiftui-outer-modifier-order.swift`,
/// arms B1, B2, D1, D2 (re-run 2026-09-16 by the integration step, every arm
/// byte-identical to its header; C0/C2 the controls):
///
/// - B1 `.frame(60x60).background`          : leaf (20, 20) 20x20, bg (0, 0) 60x60
/// - B2 `.background.frame(60x60)`          : leaf (20, 20) 20x20, bg (20, 20) 20x20
/// - D1 `.padding(8).frame(60x60).background`: leaf (20, 20) 20x20, bg (0, 0) 60x60
/// - D2 `.background.padding(8).frame(60x60)`: leaf (20, 20) 20x20, bg (20, 20) 20x20
///
/// Task 5's own list carried these as "probed, no MetalUI test". The leaf
/// paints `.surface` where it can; in B2/D2 the background IS the leaf's own
/// `Decoration.background` (a `Self`-returning modifier on the `Box`), so the
/// one accent rect stands for both. The two B arms are `#require`d to disagree
/// first. All four agree with SwiftUI.
@Test @MainActor func aBackgroundBeforeOrAfterALegacyFrameFillsTheBoxItWasWrittenOnAsSwiftUIDoes() throws {
    @MainActor func read<E: ElementGroup>(_ make: @escaping @MainActor () -> E) throws -> [String] {
        let (window, _) = try render { inRow(make) }
        let theme = window.theme
        let accent = theme[.accent]
        let surface = theme[.surface]
        return window.lastScene.rects.compactMap { r in
            let b = r.bounds
            let where_ = "(\(b.origin.x), \(b.origin.y)) \(b.size.width)x\(b.size.height)"
            if r.background.h == accent.h && r.background.s == accent.s && r.background.l == accent.l {
                return "bg " + where_
            }
            if r.background.h == surface.h && r.background.s == surface.s && r.background.l == surface.l {
                return "leaf " + where_
            }
            return nil
        }.sorted()
    }

    let b1 = try read {
        Box().width(px(20)).height(px(20)).background(.surface)
            .frame(width: px(60), height: px(60)).background(.accent)
    }
    let b2 = try read {
        Box().width(px(20)).height(px(20)).background(.accent)
            .frame(width: px(60), height: px(60))
    }
    let d1 = try read {
        Box().width(px(20)).height(px(20)).background(.surface)
            .padding(px(8)).frame(width: px(60), height: px(60)).background(.accent)
    }
    let d2 = try read {
        Box().width(px(20)).height(px(20)).background(.accent)
            .padding(px(8)).frame(width: px(60), height: px(60))
    }

    try #require(b1 != b2, why("the two frame/background orders must paint differently: \(b1) vs \(b2)"))
    #expect(b1 == ["bg (0.0, 0.0) 60.0x60.0", "leaf (20.0, 20.0) 20.0x20.0"], why("B1: \(b1)"))
    #expect(b2 == ["bg (20.0, 20.0) 20.0x20.0"], why("B2: \(b2)"))
    #expect(d1 == ["bg (0.0, 0.0) 60.0x60.0", "leaf (20.0, 20.0) 20.0x20.0"], why("D1: \(d1)"))
    #expect(d2 == ["bg (20.0, 20.0) 20.0x20.0"], why("D2: \(d2)"))
}
