import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
import MetalUIText
@testable import MetalUI

// Lane 3 of plan task 5
// (`docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`): **hit
// testing** — `allowsHitTesting(_:)` and `contentShape(inset:)`, the two
// prepaint-only modifiers of the task's eleven.
//
// Rulings: `OM-I`, `OM-J`, `OM-K`, `OM-T`, `OM-X`, `OM-AB`, `OM-AJ` and `OM-AK` in
// `docs/superpowers/2026-09-15-outer-modifiers-decisions.md`. Every SwiftUI
// expectation cites an arm of
// `docs/probes/swiftui-content-shape-hit-region.swift` or
// `docs/probes/swiftui-allows-hit-testing-side-effects.swift`, both re-recorded
// 2026-09-15 in this worktree.
//
// **What a hit region IS, in this framework**: an entry in `Frame.hitboxes`,
// registered by `Frame.registerHandlers` when `handlers.isPointerTarget` and
// the element is enabled and no `allowsHitTesting(false)` scope is open, at the
// element's own bounds (inset by `contentShapeInset` when one is declared),
// translated by the active scroll offset and intersected with the active clip.
// Every assertion below reads either that list (`Window.lastHitboxes`) or the
// end-to-end answer — a synthesized down/up pair and the handler's own counter
// — and the tests that care about the difference read both.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: Pixels(x), y: Pixels(y))
}

/// A failure message assembled from pieces — `Comment` converts a single
/// literal on its own but not a `+` concatenation of two.
private func why(_ message: String) -> Comment { "\(message)" }

/// Counts the clicks a fixture's `onClick` actually ran. A class because the
/// element that captures it is a value copied through three phases.
@MainActor
private final class ClickCounter {
    var count = 0
    func bump() { count += 1 }
}

private func describe(_ h: Hitbox) -> String {
    let b = h.bounds
    return "[\(b.origin.x.value) \(b.origin.y.value) \(b.size.width.value)x\(b.size.height.value)]"
        + " opaque=\(h.opaque) scroll=\(String(describing: h.scroll))"
}

/// Presses and releases at `point`, which is what `Window.dispatchClick`
/// requires: a click is a down and an up resolving to the same hitbox.
@MainActor
private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor private final class KeyLog { var keys: [String] = [] }

private func keyDown(_ characters: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                      modifiers: [], isRepeat: false, timestamp: 0))
}

/// The root element's id when the subject declares `.id("subject")`, and the
/// child id one level in — `FocusTests`' own idiom.
@MainActor private func subjectID() -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: ElementID("subject"))
}

@MainActor private func childID() -> GlobalElementID {
    GlobalElementID.child(of: subjectID(), at: 0, name: ElementID("child"))
}

/// Renders `element` into a collecting `Frame` — no `Window`, so no Metal
/// device — and hands back the frame with the accessibility tree built exactly
/// as `Window.drawFrameIfNeeded` builds it.
///
/// `AXEmitSiteTests`' `render` plus `collectsAccessibility: true`, which is what
/// makes a `Text`'s string observable at all: a declared `AXNode` reaches
/// `Frame.axNodes` either way, but an accessibility *client's* record — the only
/// place `accessibleText` lands — is written only while one is collecting.
@MainActor private func collect<E: Element>(_ element: E,
                                            size: Float = 200,
                                            authority: LayoutAuthority? = nil)
    -> (Frame, AccessibilityTree) {
    var element = element
    let frame = authority.map {
        Frame(contentSize: Size(width: px(size), height: px(size)), scaleFactor: 1,
              stateTable: StateTable(), shapingCache: ShapingCache(),
              glyphAtlas: GlyphAtlas(width: 256, height: 256),
              theme: Theme.forAppearance(.light), collectsAccessibility: true,
              layoutAuthority: $0)
    } ?? Frame(contentSize: Size(width: px(size), height: px(size)), scaleFactor: 1,
               stateTable: StateTable(), shapingCache: ShapingCache(),
               glyphAtlas: GlyphAtlas(width: 256, height: 256),
               theme: Theme.forAppearance(.light), collectsAccessibility: true)
    frame.render(&element)
    let tree = AccessibilityTreeBuilder.build(emissions: frame.axEmissions,
                                              focused: frame.focusedElement,
                                              hitboxes: frame.hitboxes,
                                              focusRegistry: frame.focusRegistry)
    return (frame, tree)
}

// MARK: - 1: `allowsHitTesting(false)`, the receiver and its subtree

/// What one arm of test 1 reads: the pointer side, and the keyboard side.
private struct HitReading: Equatable {
    var clicks: Int
    var regions: [String]
    var keyRan: Bool
    var focusable: Bool
}

/// Renders one arm, clicks it, then focuses `focusing` and sends a key.
///
/// **Both halves in one reading, deliberately.** The claim under test is that
/// `allowsHitTesting(false)` removes the pointer target *and nothing else*, and
/// two tests — one that saw the click, one that saw the key — could each pass
/// while the scope quietly took the other half with it on some third arm.
@MainActor
private func measure<E: Element>(clickAt: Point<Pixels>,
                                 focusing: GlobalElementID,
                                 counter: ClickCounter,
                                 log: KeyLog,
                                 authority: LayoutAuthority? = nil,
                                 _ make: @escaping @MainActor () -> E) throws -> HitReading {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    // `nil` leaves the window's default authority; a caller whose literals were
    // re-derived for `CN-J`'s centring (stage 6b, `LR-DG`) passes `.proposal`.
    let (window, platform) = try authority.map {
        try makeFakeWindow(device: device, size: 200, layoutAuthority: $0, content: make)
    } ?? makeFakeWindow(device: device, size: 200, content: make)
    window.drawFrameIfNeeded()
    let regions = window.lastHitboxes.map(describe)
    click(platform, at: clickAt)
    window.focus(focusing)
    platform.simulateInput(keyDown("x"))
    return HitReading(clicks: counter.count, regions: regions,
                      keyRan: !log.keys.isEmpty,
                      focusable: window.lastFocusRegistry.isFocusable(focusing))
}

/// **`allowsHitTesting(false)` removes the RECEIVER's own pointer target as
/// well as its subtree's, in either order, and leaves the keyboard alone**
/// (`OM-T`).
///
/// Four arms, three of them the shapes the ruling is about:
///
/// | arm | spelling | SwiftUI |
/// |---|---|---|
/// | control | `.onClick { }` | H0: centre 1 |
/// | N1 | `.onClick { }.allowsHitTesting(false)` | **centre 0, edge 0** |
/// | N2 | `.allowsHitTesting(false).onClick { }` | **centre 0, edge 0** |
/// | child | the parent scopes, the child carries the `onClick` | — |
///
/// **N1 is why the scope opens BEFORE the receiver's own registration.**
/// `.onClick` and `.allowsHitTesting` write the same `Handlers`, so a mechanism
/// that registered first and scoped only `content()` would leave N1 an opaque
/// pointer target — the common spelling, not a corner. **N2 is why this is one
/// clause and not two**: `.allowsHitTesting` wraps in SwiftUI, so a gesture
/// written outside it *could* have survived, and it does not. MetalUI's
/// one-`Handlers` storage cannot tell the two orders apart, which here is
/// agreement.
///
/// **The keyboard half is not decoration either.** SwiftUI keeps it: a `Button`
/// under `.allowsHitTesting(false)` still answers its `keyboardShortcut` and is
/// still an `AXButton` (probe `swiftui-allows-hit-testing-side-effects`, K1 and
/// A1). A scope extended to `focusRegistry.register` would read `keyRan false`
/// on all three disabled arms and nothing else in this file would notice.
@Test @MainActor
func allowsHitTestingFalseRemovesTheRECEIVERSOwnPointerTargetAndItsSubtreesAndKeepsTheKeyboardOnes() throws {
    @MainActor func subject(_ counter: ClickCounter, _ log: KeyLog) -> Box<EmptyGroup> {
        Box().width(px(100)).height(px(100)).background(.surface).id("subject")
            .focusable().onKey { _ in log.keys.append("subject"); return true }
            .onClick { counter.bump() }
    }

    let controlCounter = ClickCounter(), controlLog = KeyLog()
    let control = try measure(clickAt: pt(50, 50), focusing: subjectID(),
                              counter: controlCounter, log: controlLog) {
        subject(controlCounter, controlLog)
    }
    try #require(control.clicks == 1 && control.regions.count == 1,
                 why("the control must be hittable and must register exactly one region, or every "
                     + "zero below is the harness rather than the modifier: \(control)"))
    #expect(control.keyRan && control.focusable,
            why("and the control's keyboard half must be live: \(control)"))

    let n1Counter = ClickCounter(), n1Log = KeyLog()
    let n1 = try measure(clickAt: pt(50, 50), focusing: subjectID(),
                         counter: n1Counter, log: n1Log) {
        subject(n1Counter, n1Log).allowsHitTesting(false)
    }
    #expect(n1.clicks == 0 && n1.regions.isEmpty,
            why("N1: the receiver's OWN onClick, written before .allowsHitTesting(false), must be "
                + "dead and must register no region — SwiftUI reads centre 0 edge 0. \(n1)"))
    #expect(n1.keyRan && n1.focusable,
            why("N1: and its keyboard half must survive, as SwiftUI's K1/A1 do. \(n1)"))

    let n2Counter = ClickCounter(), n2Log = KeyLog()
    let n2 = try measure(clickAt: pt(50, 50), focusing: subjectID(),
                         counter: n2Counter, log: n2Log) {
        Box().width(px(100)).height(px(100)).background(.surface).id("subject")
            .allowsHitTesting(false)
            .focusable().onKey { _ in n2Log.keys.append("subject"); return true }
            .onClick { n2Counter.bump() }
    }
    #expect(n2 == n1,
            why("N2: the reverse order must read exactly what N1 reads — SwiftUI cannot tell them "
                + "apart either (N1 == N2 == 0/0), so MetalUI's one-Handlers storage agrees here. "
                + "N2 \(n2) vs N1 \(n1)"))

    let childCounter = ClickCounter(), childLog = KeyLog()
    let child = try measure(clickAt: pt(50, 50), focusing: childID(),
                            counter: childCounter, log: childLog) {
        Box {
            Box().width(px(100)).height(px(100)).background(.accent).id("child")
                .focusable().onKey { _ in childLog.keys.append("child"); return true }
                .onClick { childCounter.bump() }
        }
        .width(px(100)).height(px(100)).id("subject")
        .allowsHitTesting(false)
    }
    #expect(child.clicks == 0 && child.regions.isEmpty,
            why("child: the scope covers the SUBTREE too — a child's onClick inside it is dead. "
                + "\(child)"))
    #expect(child.keyRan && child.focusable,
            why("child: and the child is still focusable and still answers keys. \(child)"))
}

// MARK: - 2, 2a: every handler-registering site

/// **Every site that registers handlers honours `allowsHitTesting`** — `Box`,
/// `Stack`, `Text` and a `ModifiedElement` layer, the four callers of
/// `PrepaintPass.registerAndScope`.
///
/// One arm per site, each measured twice: with the modifier and without. A site
/// that called `registerHandlers` directly rather than through the helper would
/// register a hitbox inside an open scope and fail exactly its own arm — the
/// failure mode this repo has shipped twice already (the background chain in
/// `Box.paint` alone; the AX gate in `Box.prepaint` alone).
///
/// **The `ModifiedElement` arm puts the handlers on an INNER layer**, because
/// that is the arm a loop-shaped implementation gets wrong: `.padding(5)` then
/// the handlers then `.padding(8)` leaves the click on a layer that
/// `prepaintLayerBody` visits by recursion rather than first.
@Test @MainActor func everyHandlerRegisteringSiteHonoursAllowsHitTesting() throws {
    @MainActor func check<E: Element>(_ site: String,
                                      _ make: @escaping @MainActor (Bool, ClickCounter) -> E) throws {
        // Stage 6b (`LR-DG`, R-centre — predicted "fill", but every arm's root
        // declares 40x40): the root is centred in the 200x200 window at
        // (200 - 40) / 2 = 80, so (100, 100) is where (20, 20) was.
        let onCounter = ClickCounter(), onLog = KeyLog()
        let on = try measure(clickAt: pt(100, 100), focusing: subjectID(),
                             counter: onCounter, log: onLog,
                             authority: .proposal) { make(false, onCounter) }
        try #require(on.clicks == 1 && on.regions.count == 1,
                     why("\(site): the control must be hittable and register one region, or the "
                         + "disabled arm proves nothing: \(on)"))

        let offCounter = ClickCounter(), offLog = KeyLog()
        let off = try measure(clickAt: pt(100, 100), focusing: subjectID(),
                              counter: offCounter, log: offLog,
                              authority: .proposal) { make(true, offCounter) }
        #expect(off.clicks == 0 && off.regions.isEmpty,
                why("\(site): under .allowsHitTesting(false) this site must register nothing and "
                    + "run nothing: \(off)"))
    }

    try check("Box") { disabled, counter in
        let base = Box().width(px(40)).height(px(40)).background(.surface).id("subject")
            .onClick { counter.bump() }
        return disabled ? base.allowsHitTesting(false) : base
    }
    try check("Stack") { disabled, counter in
        let base = Stack { Box().width(px(10)).height(px(10)) }
            .width(px(40)).height(px(40)).background(.surface).id("subject")
            .onClick { counter.bump() }
        return disabled ? base.allowsHitTesting(false) : base
    }
    try check("Text") { disabled, counter in
        let base = Text("hi").width(px(40)).height(px(40)).id("subject")
            .onClick { counter.bump() }
        return disabled ? base.allowsHitTesting(false) : base
    }
    try check("ModifiedElement inner layer") { disabled, counter in
        let base = Box().width(px(30)).height(px(30)).background(.surface)
            .padding(Edges(all: .pixels(px(5))))
            .id("subject").onClick { counter.bump() }
        return (disabled ? base.allowsHitTesting(false) : base)
            .padding(Edges(all: .pixels(px(0))))
    }
}

/// **Every site still publishes its accessibility payload while the scope is
/// open** (`OM-X`, `OM-T`).
///
/// `registerAndScope` forwards `accessibleText` and `synthesizesAccessibility`
/// — a helper that took only the three-argument `registerHandlers` would delete
/// every text leaf's accessibility string — and the pointer-disable scope must
/// not take the payload with it, because `Frame.registerHandlers` gates only the
/// hitbox insert. SwiftUI agrees: a `Button` under `.allowsHitTesting(false)` is
/// still an `AXButton` with its label (probe
/// `swiftui-allows-hit-testing-side-effects`, A0 vs A1 vs the A2 control that
/// shows the walker can see a view leave the tree).
///
/// Every arm declares `.allowsHitTesting(false)` **and** an `onClick`, and each
/// asserts its own hitbox is gone in the same reading — so "the payload
/// survives" is a statement about a scope that is demonstrably open.
@Test @MainActor func everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload() throws {
    @MainActor func check<E: StyledElement>(_ site: String, _ element: E,
                                            declaring node: AXNode) {
        var element = element
        element.handlers.axNode = node
        let (frame, _) = collect(element)
        #expect(frame.hitboxes.isEmpty,
                why("\(site): set up — the scope must be open, so no hitbox may be registered; "
                    + "got \(frame.hitboxes.count)"))
        guard let emitted = frame.axNodes[subjectID()] else {
            Issue.record("\(site): declared an AXNode under .allowsHitTesting(false) and emitted none")
            return
        }
        #expect(emitted.role == node.role && emitted.label == node.label,
                why("\(site): emitted \(emitted.role)/\(emitted.label ?? "nil"), declared "
                    + "\(node.role)/\(node.label ?? "nil")"))
    }

    check("Box", Box().width(px(41)).height(px(23)).id("subject")
            .onClick { }.allowsHitTesting(false),
          declaring: AXNode(role: .button, label: "box-label"))
    check("Stack", Stack { Box().width(px(10)).height(px(10)) }
            .width(px(53)).height(px(37)).id("subject")
            .onClick { }.allowsHitTesting(false),
          declaring: AXNode(role: .image, label: "stack-label"))
    check("Text", Text("Hi").width(px(59)).height(px(19)).id("subject")
            .onClick { }.allowsHitTesting(false),
          declaring: AXNode(role: .text, label: "text-label"))
    check("ModifiedElement outermost layer",
          Box().width(px(31)).height(px(13)).padding(Edges(all: .pixels(px(4))))
            .id("subject").onClick { }.allowsHitTesting(false),
          declaring: AXNode(role: .button, label: "layer-label"))

    // The `Text` arm the ruling is actually about: the STRING, which only an
    // accessibility client's record carries and which the helper could have
    // dropped by forwarding the three-argument overload.
    let (_, tree) = collect(Text("hi").width(px(40)).height(px(20)).id("subject")
                               .onClick { }.allowsHitTesting(false))
    // A clickable text leaf is published as a BUTTON whose label is the string
    // (`AB-F`), so both members are read: which one carries it is the
    // accessibility bridge's answer, not this test's subject.
    let strings = tree.nodes.values.flatMap { [$0.value, $0.label].compactMap { $0 } }
    #expect(strings.contains("hi"),
            why("the text leaf's string must still reach an accessibility client under "
                + "allowsHitTesting(false): published label/value strings were \(strings)"))
}

// MARK: - 3, 4, 5: the content shape

/// **A content-shape inset shrinks the hit region and changes no layout and no
/// paint** (`OM-J`; probe H3, and L7 for the layout-neutrality).
///
/// SwiftUI H2 vs H3: `.contentShape(Rectangle())` reads centre 1 / edge 1 and
/// `.contentShape(Rectangle().inset(by: 60))` reads centre 1 / **edge 0** on the
/// same 200x200 subject. MetalUI's default is H2's, so the inset is the whole of
/// what this modifier adds, and the numbers below are H3's shape at a 100x100
/// box and a 20pt inset.
///
/// The rects emitted by the two arms are compared **byte for byte**: SwiftUI's
/// `.contentShape` leaves a 20x20 leaf 20x20 (L7) and MetalUI's must likewise
/// move nothing the engine produced and emit nothing new.
@Test @MainActor func aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    // The `Window` is returned and held, not only its platform: `Window` is
    // what owns the input path, and a fixture that dropped it would deliver no
    // clicks at all — which reads as "the modifier removed the hit region" on
    // every arm at once.
    @MainActor func arm(counter: ClickCounter,
                        _ shape: @escaping @MainActor (Box<EmptyGroup>) -> Box<EmptyGroup>)
        throws -> (regions: [String], rects: [String], window: Window, platform: FakePlatformWindow) {
        // Stage 6b (`LR-DG`, R-centre): the 100x100 root is centred in the
        // 200x200 window at (200 - 100) / 2 = 50; every literal below is the
        // legacy top-left one moved by 50 on both axes.
        let (window, platform) = try makeFakeWindow(device: device, size: 200,
                                                    layoutAuthority: .proposal) {
            shape(Box().width(px(100)).height(px(100)).background(.surface).id("subject")
                    .onClick { counter.bump() })
        }
        window.drawFrameIfNeeded()
        return (window.lastHitboxes.map(describe),
                window.lastScene.rects.map { "\($0.bounds.origin.x),\($0.bounds.origin.y) "
                    + "\($0.bounds.size.width)x\($0.bounds.size.height)" },
                window, platform)
    }

    let plainCounter = ClickCounter()
    let plain = try arm(counter: plainCounter) { $0 }
    let shapedCounter = ClickCounter()
    let shaped = try arm(counter: shapedCounter) { $0.contentShape(inset: px(20)) }

    try #require(plain.regions != shaped.regions,
                 why("the two arms must register different regions, or nothing here is measuring "
                     + "the modifier: \(plain.regions) vs \(shaped.regions)"))
    #expect(plain.regions == ["[50.0 50.0 100.0x100.0] opaque=true scroll=nil"],
            why("the control registers the element's whole box: \(plain.regions)"))
    #expect(shaped.regions == ["[70.0 70.0 60.0x60.0] opaque=true scroll=nil"],
            why("and a 20pt inset registers the inset box: \(shaped.regions)"))

    #expect(plain.rects == shaped.rects,
            why("a content shape is prepaint-only: it must emit nothing and move nothing the "
                + "engine produced, as SwiftUI's leaves a 20x20 leaf 20x20 (L7). "
                + "\(plain.rects) vs \(shaped.rects)"))

    click(plain.platform, at: pt(55, 100))
    click(shaped.platform, at: pt(55, 100))
    #expect(plainCounter.count == 1,
            "the edge point hits the control (SwiftUI H2, edge 1)")
    #expect(shapedCounter.count == 0,
            "and misses the inset one (SwiftUI H3, edge 0)")

    click(shaped.platform, at: pt(100, 100))
    #expect(shapedCounter.count == 1,
            "while the centre still hits (SwiftUI H3, centre 1)")

    // The per-edge overload, with FOUR DISTINCT insets (taxonomy shape 1: a
    // uniform 20 above cannot see `hitRegion` reading `left` for `right` or
    // `top` for `bottom`). 5 / 10 / 15 / 20 on a 100x100 box at (50, 50) leaves
    // the region x in [70, 140), y in [55, 135), and each click below is placed
    // so that exactly one edge decides it: (65, 100) is inside a 10pt left inset
    // and outside a 20pt one; (142, 100) is inside a 5pt right inset and outside
    // a 10pt one; (75, 57) is inside a 5pt top inset and outside a 10pt one;
    // (100, 137) is inside a 10pt bottom inset and outside a 15pt one.
    let edgedCounter = ClickCounter()
    let edged = try arm(counter: edgedCounter) {
        $0.contentShape(inset: Edges(top: px(5), right: px(10), bottom: px(15), left: px(20)))
    }
    #expect(edged.regions == ["[70.0 55.0 70.0x80.0] opaque=true scroll=nil"],
            why("a per-edge inset of top 5 / right 10 / bottom 15 / left 20 registers "
                + "(70, 55) 70x80: \(edged.regions)"))
    #expect(edged.rects == plain.rects,
            why("and, like the uniform one, emits nothing and moves nothing: "
                + "\(edged.rects) vs \(plain.rects)"))
    click(edged.platform, at: pt(65, 100))
    #expect(edgedCounter.count == 0, "left inset 20: x = 65 (15 into the box) misses")
    click(edged.platform, at: pt(142, 100))
    #expect(edgedCounter.count == 0, "right inset 10: x = 142 (92 into the box) misses")
    click(edged.platform, at: pt(75, 57))
    #expect(edgedCounter.count == 1, "top inset 5: (75, 57) — (25, 7) into the box — hits")
    click(edged.platform, at: pt(100, 137))
    #expect(edgedCounter.count == 1, "bottom inset 15: y = 137 (87 into the box) misses")
}

/// **A negative inset GROWS the hit region past the element's box, and the
/// grown region is still bounded by an ancestor's clip** (`OM-J`, `OM-AJ`).
///
/// SwiftUI H4 vs H5: an 80x80 leaf reads edge 0, and the same leaf at
/// `.contentShape(Rectangle().inset(by: -60))` reads **edge 1** — a point 40pt
/// outside it. So growing is not a MetalUI invention.
///
/// **The clip half is a divergence, and it is measured rather than assumed**
/// (H6): SwiftUI's grown region survives an ancestor `.clipped()` and hits
/// through it; MetalUI's does not, because `Frame.insertHitbox` intersects
/// every registered region with the active clip — the rule that keeps a hitbox
/// from covering content the element does not draw. Pinned here, recorded as
/// `OM-AJ`.
///
/// The fixture is a 40x40 clickable child, inset by **-100**, inside an 80x80
/// `.clipped()` parent: (60, 60) is outside the child and inside the parent;
/// (100, 100) is outside both. Stage 6b (`LR-DG`, R-centre): the 80x80 root is
/// centred in the 200x200 window at (200 - 80) / 2 = 60, so every literal is
/// moved by 60 — the child at (60, 60), the points (120, 120) and (160, 160).
@Test @MainActor func aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    // The `Window` is held for `aContentShapeInsetShrinksTheHitRegion...`'s
    // reason: dropping it drops the input path and every arm reads zero.
    @MainActor func arm(_ inset: Pixels?, counter: ClickCounter)
        throws -> (regions: [String], window: Window, platform: FakePlatformWindow) {
        let (window, platform) = try makeFakeWindow(device: device, size: 200,
                                                    layoutAuthority: .proposal) {
            Box {
                let base = Box().width(px(40)).height(px(40)).background(.accent).id("child")
                    .onClick { counter.bump() }
                return inset.map { base.contentShape(inset: $0) } ?? base
            }
            .width(px(80)).height(px(80)).background(.surface).id("subject").clipped()
        }
        window.drawFrameIfNeeded()
        return (window.lastHitboxes.map(describe), window, platform)
    }

    let plainCounter = ClickCounter()
    let plain = try arm(nil, counter: plainCounter)
    let grownCounter = ClickCounter()
    let grown = try arm(px(-100), counter: grownCounter)

    try #require(plain.regions != grown.regions,
                 why("the two arms must register different regions: \(plain.regions) vs "
                     + "\(grown.regions)"))
    #expect(plain.regions == ["[60.0 60.0 40.0x40.0] opaque=true scroll=nil"],
            why("the control registers the child's own 40x40 box: \(plain.regions)"))
    #expect(grown.regions == ["[60.0 60.0 80.0x80.0] opaque=true scroll=nil"],
            why("a -100 inset grows the region to (-100, -100) 240x240 and the parent's clip "
                + "bounds it to the parent's own 80x80 — SwiftUI's clip would not (H6): "
                + "\(grown.regions)"))

    click(plain.platform, at: pt(120, 120))
    #expect(plainCounter.count == 0,
            "a point outside the 40x40 child misses it (SwiftUI H4, edge 0)")
    click(grown.platform, at: pt(120, 120))
    #expect(grownCounter.count == 1,
            "and hits the grown region (SwiftUI H5, edge 1)")

    click(grown.platform, at: pt(160, 160))
    #expect(grownCounter.count == 1,
            why("while a point outside the ancestor's clip does not — MetalUI clips the grown "
                + "region where SwiftUI's H6 hits through it"))
}

/// **A content shape moves the hit region and NOTHING else** (`OM-J`): not the
/// accessibility frame a client publishes, not the emitted `AXNode`'s frame, and
/// not the focus registration.
///
/// The inset is applied inside `Frame.registerHandlers`, to the bounds handed to
/// `insertHitbox` alone. Applying it to `bounds` at the call site instead —
/// which is the obvious implementation — would move all four together and this
/// is the only test that would see it.
///
/// The hit region's move is `#require`d first: without that, every "still
/// 100x100" below would pass against a modifier that did nothing at all.
@Test @MainActor func aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration() throws {
    var element = Box().width(px(100)).height(px(100)).id("subject")
        .onClick { }.focusable().contentShape(inset: px(20))
    element.handlers.axNode = AXNode(role: .button, label: "shaped")
    // Stage 6b (`LR-DG`, R-centre): the 100x100 root is centred in the 200x200
    // frame at (200 - 100) / 2 = 50.
    let (frame, tree) = collect(element, authority: .proposal)

    let hit = try #require(frame.hitboxes.first, "the element declares an onClick and must register")
    try #require(hit.bounds.size.width.value == 60 && hit.bounds.size.height.value == 60,
                 why("set up: the hit region must have MOVED to 60x60, or 'nothing else moved' is "
                     + "vacuous — got \(describe(hit))"))

    let node = try #require(frame.axNodes[subjectID()], "a declared AXNode must be emitted")
    #expect(node.frame.origin.x.value == 50 && node.frame.origin.y.value == 50
                && node.frame.size.width.value == 100 && node.frame.size.height.value == 100,
            why("the emitted AXNode keeps the element's own box, not the inset one: \(node.frame)"))

    let geometry = tree.nodes.keys.compactMap { tree.geometry[$0] }
    #expect(geometry.contains { $0.frame.size.width.value == 100 && $0.frame.size.height.value == 100 },
            why("and so does the record an accessibility client reads: "
                + "\(geometry.map(\.frame))"))

    #expect(frame.focusRegistry.isFocusable(subjectID()),
            "and the element is still in the focus registry, which carries no geometry to move")
}

// MARK: - 6a: a content shape creates nothing

/// **A content shape with no click handler registers nothing, and that is
/// documented rather than fixed** (`OM-AB`).
///
/// `onClick(_:)` remains the only thing that makes an element a pointer target;
/// this modifier configures a region another modifier creates. The repo already
/// names the identical shape one field over —
/// `hoverBackgroundWithoutAClickHandlerNeverPaints` — and SwiftUI's
/// `.contentShape` on a gesture-less view is inert for the same reason: nothing
/// is listening.
///
/// The control is the same element with an `onClick`, so "registers nothing" is
/// a statement about the missing handler rather than about a fixture that never
/// reached prepaint.
@Test @MainActor func aContentShapeWithoutAClickHandlerRegistersNothing() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    // Stage 6b (`LR-DG`, R-centre): the 40x40 root is centred in the 100x100
    // window at (100 - 40) / 2 = 30, so the 10pt-inset region is (40, 40) 20x20.
    let (bare, _) = try makeFakeWindow(device: device, size: 100, layoutAuthority: .proposal) {
        Box().width(px(40)).height(px(40)).background(.surface).id("subject")
            .contentShape(inset: px(10))
    }
    bare.drawFrameIfNeeded()
    #expect(bare.lastHitboxes.isEmpty,
            why("a content shape does not create a hit region: "
                + bare.lastHitboxes.map(describe).joined(separator: " | ")))

    let (clickable, _) = try makeFakeWindow(device: device, size: 100, layoutAuthority: .proposal) {
        Box().width(px(40)).height(px(40)).background(.surface).id("subject")
            .contentShape(inset: px(10)).onClick { }
    }
    clickable.drawFrameIfNeeded()
    #expect(clickable.lastHitboxes.map(describe) == ["[40.0 40.0 20.0x20.0] opaque=true scroll=nil"],
            why("while the same element WITH an onClick registers the configured region: "
                + clickable.lastHitboxes.map(describe).joined(separator: " | ")))
}

// MARK: - OM-AK: what the scope does not reach

/// **A `ScrollView` inside an `allowsHitTesting(false)` scope still registers
/// its scroll region, and still scrolls** — recorded, not fixed (`OM-AK`).
///
/// `Frame.registerScrollRegion` reaches `insertHitbox` directly; only
/// `registerHandlers` consults `hitTestingDisabledDepth`. The hole is older than
/// this lane — the proposal path's `.allowsHitTesting` has always had it — but
/// lane 3 changes its REACH, from "a proposal subtree" to "any legacy element",
/// which is `OM-U`'s shape one modifier over. It is pinned rather than fixed
/// because the fix is a different call site than this lane's brief names and
/// SwiftUI evidence for a scrolling `ScrollView` under `.allowsHitTesting(false)`
/// has not been taken.
///
/// The control is the same fixture without the modifier: both scroll, and both
/// register one region, so this test says "the scope reached neither", not "the
/// fixture never scrolled".
@Test @MainActor func aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    @MainActor func arm(_ disabled: Bool) throws -> (scrollRegions: Int, offset: Float) {
        let (window, platform) = try makeFakeWindow(device: device, size: 100) {
            let base = Box {
                ScrollView(.vertical, elementID: ElementID("scroller")) {
                    Box().width(px(100)).height(px(400)).flexShrink(0).background(.accent)
                }
            }
            .width(px(100)).height(px(100)).id("subject")
            return disabled ? base.allowsHitTesting(false) : base
        }
        window.drawFrameIfNeeded()
        platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(50, 50),
                                                        delta: pt(0, -40),
                                                        isMomentum: false)))
        window.drawFrameIfNeeded()
        let regions = window.lastHitboxes.filter { $0.scroll != nil }
        let offset = window.lastScene.rects.first { $0.bounds.size.height == 400 }?.bounds.origin.y
        return (regions.count, offset ?? 0)
    }

    let control = try arm(false)
    try #require(control.scrollRegions == 1 && control.offset != 0,
                 why("set up: the control must register one scroll region and must actually "
                     + "scroll, got \(control)"))

    let scoped = try arm(true)
    #expect(scoped.scrollRegions == 1,
            why("PINNED WRONG ON PURPOSE (OM-AK): registerScrollRegion does not consult "
                + "hitTestingDisabledDepth, so the region survives the scope. Got \(scoped)"))
    #expect(scoped.offset == control.offset,
            why("and the wheel still scrolls it by the same amount. Got \(scoped) vs \(control)"))
}

// MARK: - 6: MetalUI's default hit region

/// **MetalUI's default hit region is the element's whole frame, and SwiftUI's
/// is derived from what the view draws** (`OM-I`) — pinned wrong on purpose.
///
/// Probe `swiftui-content-shape-hit-region`, the H arms:
///
/// | arm | SwiftUI |
/// |---|---|
/// | H1 a 200x200 stack with an empty middle + `.onTapGesture` | centre **0**, edge **0** |
/// | H2 the same + `.contentShape(Rectangle())` | centre 1, edge 1 |
///
/// The fixture below is H1's shape in MetalUI: a 200x200 `Column` with
/// `justifyContent(.spaceBetween)`, a `Text` at each end, no background
/// anywhere, and one `onClick`. It reads **1 / 1** — H2's numbers, from the
/// spelling that is H1. So MetalUI's default already IS
/// `.contentShape(Rectangle())`, which is why `contentShape(inset:)` and not
/// `contentShape(Rectangle())` is the modifier lane 3 ships (`OM-J`): the
/// SwiftUI spelling would compile and do nothing.
///
/// **The emptiness of the middle is asserted, not assumed.** Without that, "a
/// click at the centre hits" would be true of a fixture that painted a
/// background across the whole box, and the test would be about nothing. No
/// rect is emitted at all (an undecorated `Column` emits none) and no glyph's
/// bounds come within 40pt of the centre.
@Test @MainActor func metalUIsDefaultHitRegionIsTheElementsWholeFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let counter = ClickCounter()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Column {
            Text("top")
            Text("bottom")
        }
        .width(px(200)).height(px(200))
        .justifyContent(.spaceBetween)
        .onClick { counter.bump() }
    }
    window.drawFrameIfNeeded()

    let scene = window.lastScene
    let centre = pt(100, 100)
    try #require(scene.rects.isEmpty,
                 why("set up: the fixture must paint no rect at all, or 'the middle is empty' "
                     + "is not established — got \(scene.rects.count)"))
    let nearCentre = scene.glyphs.filter {
        let b = $0.bounds
        return abs(b.origin.y + b.size.height / 2 - 100) < 40
    }
    try #require(nearCentre.isEmpty,
                 why("set up: no glyph may be drawn within 40pt of the centre, or this is not "
                     + "SwiftUI's H1 shape — got \(nearCentre.count)"))

    click(platform, at: centre)
    #expect(counter.count == 1,
            why("a click in the empty middle must hit: MetalUI's hit region is the whole 200x200 "
                + "frame. SwiftUI's H1 reads 0 here and needs .contentShape(Rectangle()) (H2) to "
                + "read 1. Hitboxes: " + window.lastHitboxes.map(describe).joined(separator: " | ")))

    click(platform, at: pt(20, 100))
    #expect(counter.count == 2,
            why("and a click at the edge point the probe uses, for the same reason (SwiftUI H1 "
                + "edge 0). Hitboxes: "
                + window.lastHitboxes.map(describe).joined(separator: " | ")))

    let regions = window.lastHitboxes.map(describe)
    #expect(regions == ["[0.0 0.0 200.0x200.0] opaque=true scroll=nil"],
            why("and the region registered is the element's own box, not a shape derived from "
                + "what it painted: " + regions.joined(separator: " | ")))
}

// MARK: - OM-AL: what the scope does not reach, across a layer

/// **An inner layer's `allowsHitTesting(false)` does not reach an `onClick` on
/// a layer written after it, and SwiftUI's does** — a recorded divergence
/// (`OM-AL`), derived from `OM-I` rather than a new mechanism.
///
/// Probe `swiftui-content-shape-hit-region`, the X arms (120x120 colour,
/// padding 40, 200x200 window; centre (100, 100), edge (20, 100) in the
/// padding):
///
/// | arm | spelling | SwiftUI | MetalUI |
/// |---|---|---|---|
/// | X0 | `.padding(40).onClick` (control) | 1 / 0 | 1 / 1 (`OM-K`) |
/// | X1 | `.allowsHitTesting(false).padding(40).onClick` | **0 / 0** | **1 / 1** |
/// | X2 | `.padding(40).allowsHitTesting(false).onClick` | 0 / 0 | 0 / 0 |
/// | X3 | X1 + `.contentShape(Rectangle())` before the tap | 1 / 1 | — (MetalUI's X1) |
///
/// `OM-T`'s "the order is not observable" holds within ONE `ModifierLayer`:
/// N1 and N2 both land on the outermost layer's `Handlers`. Here `.padding`
/// sits between them, so X1's scope is on the inner layer and its click on the
/// outer one; `registerAndScope` opens the scope when it reaches the inner
/// layer, after the outer layer has already registered a live 200x200 hitbox.
/// X2 puts both on the outer layer and is N1 again.
///
/// **Why it is not fixed**: X3. SwiftUI's modifier empties the subtree's hit
/// REGION and does not kill a later gesture — a `.contentShape(Rectangle())`
/// after the padding gives it a region again and X3 reads 1/1. MetalUI's
/// default region is always the frame (`OM-I`), so its X1 answer is SwiftUI's
/// X3; a scope that suppressed the layers written after it would reproduce X1
/// and contradict X3 in the same stroke.
///
/// The X1 and X2 arms are `#require`d to DISAGREE before either number is
/// asserted: a mechanism that made the inner scope reach outward would make
/// them agree at 0/0, and that is the one change this test exists to notice.
@Test @MainActor func anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    // A 120x120 colour padded by 40 in a 200x200 window: the probe's X shape.
    @MainActor func arm(_ counter: ClickCounter,
                        _ chain: @escaping @MainActor (Box<EmptyGroup>) -> ModifiedElement<Box<EmptyGroup>>)
        throws -> (centre: Int, edge: Int, regions: [String]) {
        let (window, platform) = try makeFakeWindow(device: device, size: 200) {
            chain(Box().width(px(120)).height(px(120)).background(.accent).id("subject"))
        }
        window.drawFrameIfNeeded()
        let regions = window.lastHitboxes.map(describe)
        click(platform, at: pt(100, 100))
        let centre = counter.count
        click(platform, at: pt(20, 100))
        return (centre, counter.count - centre, regions)
    }

    let x0Counter = ClickCounter()
    let x0 = try arm(x0Counter) { $0.padding(px(40)).onClick { x0Counter.bump() } }
    try #require(x0.centre == 1 && x0.edge == 1 && x0.regions.count == 1,
                 why("X0, the control: the padded click target must be live at both points "
                     + "(SwiftUI 1/0, MetalUI 1/1 by OM-K), or every reading below is the "
                     + "harness: \(x0)"))

    let x1Counter = ClickCounter()
    let x1 = try arm(x1Counter) {
        $0.allowsHitTesting(false).padding(px(40)).onClick { x1Counter.bump() }
    }
    let x2Counter = ClickCounter()
    let x2 = try arm(x2Counter) {
        $0.padding(px(40)).allowsHitTesting(false).onClick { x2Counter.bump() }
    }

    try #require(x1 != x2,
                 why("the two orders must DISAGREE, or the inner layer's scope has started reaching "
                     + "the layers written after it — which is not a fix (probe X3): X1 \(x1) vs "
                     + "X2 \(x2)"))
    #expect(x1.centre == 1 && x1.edge == 1
                && x1.regions == ["[0.0 0.0 200.0x200.0] opaque=true scroll=nil"],
            why("PINNED WRONG ON PURPOSE (OM-AL): .allowsHitTesting(false).padding(40).onClick "
                + "scopes the INNER layer and registers the OUTER layer's 200x200 hitbox live — "
                + "SwiftUI's X1 reads 0/0. \(x1)"))
    #expect(x2.centre == 0 && x2.edge == 0 && x2.regions.isEmpty,
            why("X2: the reverse order puts both on the outer layer and is N1 again — 0/0, no "
                + "region, as SwiftUI's X2. \(x2)"))
}

// MARK: - hover follows the hitbox

/// **A `hoverBackground` on an element under `allowsHitTesting(false)` never
/// paints**, because hover is resolved from the hitbox list and the element
/// registers no hitbox — the sentence in `StyledElement.allowsHitTesting`'s
/// doc comment, pinned (lane 3's review round).
///
/// Two arms under one `mouseMoved` over the subject: the control paints its
/// hover colour and the scoped arm paints its plain background. The control
/// is `#require`d to be hovered first, so "never paints" is a statement about
/// the scope and not about a pointer that never arrived.
/// `everyBackgroundPaintingSiteHonoursHoverAndFocus` owns the hover chain per
/// site; this test owns the one modifier that removes its input.
@Test @MainActor func aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    @MainActor func fill(_ disabled: Bool) throws -> String {
        // Stage 6b (`LR-DG`, R-centre): the 40x40 root is centred at 30..70.
        let (window, platform) = try makeFakeWindow(device: device, size: 100,
                                                    layoutAuthority: .proposal) {
            let base = Box().width(px(40)).height(px(40))
                .background(.surface).hoverBackground(.accent).id("subject").onClick { }
            return disabled ? base.allowsHitTesting(false) : base
        }
        window.drawFrameIfNeeded()
        platform.simulateInput(.mouseMoved(MouseEvent(position: pt(50, 50))))
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        let rect = try #require(window.lastScene.rects.first {
            $0.bounds.size.width == 40 && $0.bounds.size.height == 40
        }, "the subject painted no 40x40 rect")
        let theme = window.theme
        for token in [ColorToken.surface, .accent] {
            let want = theme[token]
            if rect.background.h == want.h && rect.background.s == want.s
                && rect.background.l == want.l && rect.background.a == want.a {
                return "\(token)"
            }
        }
        return "neither surface nor accent: \(rect.background)"
    }

    let control = try fill(false)
    try #require(control == "accent",
                 why("set up: the hovered control must paint its hoverBackground, or the scoped "
                     + "arm's plain fill says nothing about the scope — painted \(control)"))
    let scoped = try fill(true)
    #expect(scoped == "surface",
            why("under .allowsHitTesting(false) the element registers no hitbox, is never hovered, "
                + "and its hoverBackground never paints — painted \(scoped)"))
}
