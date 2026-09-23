import Testing
import Metal
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI

// Plan task 7, stage 5 of the engine replacement — **lane 3**, the must-not-move
// set through real windows. Design: `docs/superpowers/specs/2026-09-23-engine-stage-5-design.md`
// §5.1 and §7 lane 3 (ruling `LR-CO`; corrections `LR-CS`).
//
// Every scenario runs under **both** layout authorities, as `@Test(arguments:)`
// cases recorded in `AuthorityCoverage`. Under the proposal authority a `Deferred`
// whose content is `.position(.absolute)` is a presentation root laid out against
// the window (`LR-CH`, `LR-CI`, `LR-CM`); these tests hold that what a WINDOW does
// with it afterwards — dispatch, the wheel, opacity, environment, accessibility,
// focus, animation and the layer — is what the legacy authority does.
//
// **A window builds production frames**, so under the proposal authority an
// unlowerable field traps and ends the run with no summary line (`LR-BX`). Every
// window here is opened only after the same content's `LayoutDifferential.compare`
// report is `try #require`d empty (`presentationWindow`), and an animated tree is
// pre-flighted in each of its two end states.
//
// **Hosted in `DifferentialRoot`** (window-sized, top-leading) for the reason
// `WindowPair` gives: a native root is centred at its own answer (`CN-J`,
// divergence 4, stage 6b's), so an in-flow sibling would otherwise sit elsewhere
// under the proposal authority. The presentation itself is laid out against the
// window whatever the root. **3.1 is the exception**: it is the demo, as
// production shows it, with `demoContent()` as the window's root, so it
// pre-flights the root-level frame as well.
//
// **This file imports `Metal`**, so no fixture spells `Dimension` bare
// (`Fakes.swift`'s note): insets are written with `pxDim`.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pxDim(_ v: Float) -> MetalUICore.Dimension { .length(.pixels(Pixels(v))) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h)))
}
private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: b.origin.x + b.size.width / 2, y: b.origin.y + b.size.height / 2)
}
private func edges(top: MetalUICore.Dimension = .auto, right: MetalUICore.Dimension = .auto,
                   bottom: MetalUICore.Dimension = .auto,
                   left: MetalUICore.Dimension = .auto) -> Edges<MetalUICore.Dimension> {
    Edges(top: top, right: right, bottom: bottom, left: left)
}

@MainActor
private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

private func wheel(at position: Point<Pixels>, deltaY: Float) -> InputEvent {
    .scrollWheel(ScrollEvent(position: position, delta: Point(x: Pixels(0), y: Pixels(deltaY))))
}

private func keyDown(_ characters: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                      modifiers: [], timestamp: 0))
}

@MainActor
private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

@MainActor
private func drawUntilClean(_ window: Window, limit: Int = 5) {
    for _ in 0..<limit where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// A `size`×`size` fake window under `authority` showing `DifferentialRoot { make() }`,
/// opened only after the same content's differential report is empty — the
/// pre-flight that keeps a proposal-authority regression a failure rather than an
/// abort (`LR-BX`). Not drawn yet: the caller draws.
@MainActor
private func presentationWindow<C: ElementGroup>(
    _ authority: LayoutAuthority, size: Int = 200, startsDisplayLink: Bool = false,
    sourceLocation: SourceLocation = #_sourceLocation,
    @ElementBuilder _ make: @escaping @MainActor () -> C
) throws -> (window: Window, platform: FakePlatformWindow) {
    let preflight = LayoutDifferential.compare(width: Float(size), height: Float(size), make)
    try #require(preflight.unlowerable.isEmpty,
                 "this tree would trap in a proposal-authority window: \(preflight.unlowerable)",
                 sourceLocation: sourceLocation)
    let device = try #require(MTLCreateSystemDefaultDevice(), sourceLocation: sourceLocation)
    let (window, platform) = try makeFakeWindow(device: device, size: size,
                                                startsDisplayLink: startsDisplayLink,
                                                layoutAuthority: authority) {
        DifferentialRoot(width: Float(size), height: Float(size), content: make)
    }
    window.recordsElementBounds = true
    return (window, platform)
}

/// The one rect in `scene` whose size is `w`×`h`.
private func rect(_ scene: Scene, _ w: Float, _ h: Float,
                  sourceLocation: SourceLocation = #_sourceLocation) throws -> MUIRect {
    let matches = scene.rects.filter { $0.bounds.size.width == w && $0.bounds.size.height == h }
    try #require(matches.count == 1, "expected one \(w)×\(h) rect, got \(matches.count)",
                 sourceLocation: sourceLocation)
    return matches[0]
}

private func hsla(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }

@MainActor
private final class Log {
    var names: [String] = []
}

// MARK: - 3.1 The demo modal: click-to-dismiss and the wheel (IN-W)

/// **3.1** (`IN-W`, `AP-I`). The demo exactly as production shows it —
/// `demoContent()` as the root of a 920 window — with the modal up:
///
/// - the topmost opaque hitbox at a point over the `List` and outside the card is
///   the scrim's, at the whole window, on layer 1;
/// - a wheel there is **claimed and scrolls nothing** (the list stays at 0);
/// - a click on the card keeps the modal; a click on the scrim dismisses it;
/// - and — the separating arm — once dismissed, the same wheel at the same point
///   scrolls the list by 37, so the point really is over the list.
///
/// **Pre-flighted twice, in both modal states**: through `LayoutDifferential.compare`
/// and as the frame's root under diagnostics, because this window's root is the
/// demo itself rather than the harness root (whose native node is the window by
/// construction, `LR-CL`).
///
/// Red-before: lane 1's branch disabled, the pre-flight reads `[stack.position,
/// stack.inset]` (spec §7). Mutation that must redden it: **M1c** (W not aliased:
/// the scrim's hitbox shrinks to the card-sized stack, the wheel reaches the list).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func theDemoModalDismissesOnAScrimClickAndSwallowsTheWheelUnderBothAuthorities(
    _ authority: LayoutAuthority
) throws {
    AuthorityCoverage.record(#function, authority)
    demoModel.animationDemoActive = false
    defer { demoModel.showModal = false }
    for modal in [true, false] {
        demoModel.showModal = modal
        let report = LayoutDifferential.compare(width: 920, height: 920) { demoContent() }
        try #require(report.unlowerable.isEmpty, "modal \(modal): \(report.unlowerable)")
        var root = demoContent()
        let rooted = Frame(contentSize: Size(width: px(920), height: px(920)), scaleFactor: 1,
                           layoutAuthority: .proposal, reportsUnlowerableFields: true)
        rooted.render(&root)
        try #require(rooted.unlowerableFields.isEmpty, "modal \(modal), as the root: \(rooted.unlowerableFields)")
    }

    demoModel.showModal = true
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 920, layoutAuthority: authority) {
        demoContent()
    }
    window.drawFrameIfNeeded()

    let windowRect = bounds(0, 0, 920, 920)
    let listRegion = try #require(window.lastScrollRegions.first { $0.bounds.size.height > 100 },
                                  "the demo's List scroller must register a region")
    let list = listRegion.id
    let p = pt(listRegion.bounds.origin.x.value + 4, listRegion.bounds.origin.y.value + 4)
    let scrimIndex = try #require(topmostOpaqueHitbox(in: window.lastHitboxes, at: p))
    let scrim = window.lastHitboxes[scrimIndex]
    #expect(scrim.bounds == windowRect && scrim.layer == 1,
            "\(authority): over the list, outside the card, the scrim's hitbox is the window on layer 1; got \(scrim.bounds) layer \(scrim.layer)")
    let cardIndex = try #require(topmostOpaqueHitbox(in: window.lastHitboxes, at: pt(460, 460)))
    let card = window.lastHitboxes[cardIndex]
    try #require(card.bounds.size.width == 360 && card.layer == 1,
                 "\(authority): the card's hitbox wins at the window's centre; got \(card.bounds)")
    try #require(!card.bounds.contains(p), "set up: the wheel point is outside the card")

    let claimed = platform.simulateInput(wheel(at: p, deltaY: -37))
    #expect(claimed, "\(authority): the wheel over the scrim is claimed")
    #expect((window.stateTable.peek(list, as: ScrollState.self)?.offset ?? 0) == 0,
            "\(authority): and the list under the scrim does not move (IN-W)")

    click(platform, at: centre(card.bounds))
    #expect(demoModel.showModal, "\(authority): a click on the card keeps the modal")
    click(platform, at: p)
    #expect(!demoModel.showModal, "\(authority): a click on the scrim dismisses it")

    window.drawFrameIfNeeded()
    #expect(!window.lastHitboxes.contains { $0.bounds == windowRect && $0.layer == 1 },
            "\(authority): the scrim is gone")
    platform.simulateInput(wheel(at: p, deltaY: -37))
    #expect(window.stateTable.peek(list, as: ScrollState.self)?.offset == 37,
            "\(authority): the separating arm — without the scrim the same wheel scrolls the list")
}

// MARK: - 3.2 Opacity is not reset (OM-AA)

/// **3.2** (`OM-AA`, divergence 46). A presentation declared inside a subtree
/// faded to 0.5 is faded with it: `Deferred` resets the clip, the translation and
/// the layer, **not** the opacity stack — and a presentation laid out in its own
/// run (`LR-CM`) still paints inside its declaring element's paint call.
///
/// The presentation sits at the window's (10, 10), outside the faded 40×40 box at
/// x 50, so it is shown to be laid out against the window rather than inside the
/// box. The control is the same tree unfaded (a semi-transparent token would pass
/// "half" on its own).
///
/// Mutation that must redden it: **M3a** (`pass.deferred` resets the opacity
/// stack; both authorities).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aPresentationInsideAFadedSubtreeIsStillFadedUnderBothAuthorities(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func portal(faded: Bool) throws -> MUIRect {
        let (window, _) = try presentationWindow(authority) {
            Row {
                Box().width(px(50)).height(px(50)).background(.surface)
                Box {
                    Deferred {
                        Box().width(px(20)).height(px(20)).background(.accent)
                            .position(.absolute).inset(edges(top: pxDim(10), left: pxDim(10)))
                    }
                }
                .width(px(40)).height(px(40))
                .opacity(faded ? 0.5 : 1)
            }
            .alignItems(.flexStart)
        }
        window.drawFrameIfNeeded()
        return try rect(window.lastScene, 20, 20)
    }
    let plain = try portal(faded: false), faded = try portal(faded: true)
    try #require(plain.background.a > 0, "\(authority): set up — the presentation paints")
    #expect(plain.bounds.origin.x == 10 && plain.bounds.origin.y == 10
                && faded.bounds.origin.x == 10 && faded.bounds.origin.y == 10,
            "\(authority): laid out against the window at (10, 10)")
    #expect(abs(faded.background.a - plain.background.a * 0.5) < 0.001,
            "\(authority): OM-AA — expected \(plain.background.a * 0.5), got \(faded.background.a)")
}

// MARK: - 3.3 The declaring scope's environment and `.disabled` carry through

/// **3.3** (`EV-`, `EV-D`; probe F1 via E12). A presentation declared inside a
/// `.theme(.dark)` scope paints dark while a sibling outside it paints light, and
/// one declared inside `.disabled(true)` registers no hitbox, takes no click and
/// cannot be focused — each against its own control (`.disabled(false)`: one
/// click, focus held).
///
/// Mutation that must redden it: **M3b** (spec §7: `Deferred.requestLayout` wraps
/// its content in the root environment; lane 3's corrections, `LR-CS`, say what
/// that spelling does and does not reach).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aPresentationKeepsItsDeclaringScopesEnvironmentUnderBothAuthorities(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func run(disabled: Bool) throws -> (clicks: Int, focused: Bool, hit: Bool, colour: Hsla, outside: Hsla) {
        let log = Log()
        let (window, platform) = try presentationWindow(authority) {
            Row {
                Box().width(px(11)).height(px(10)).background(.surface)
                Deferred {
                    Box().width(px(30)).height(px(30)).background(.surface)
                        .focusable().onClick { log.names.append("x") }
                        .position(.absolute).inset(edges(top: pxDim(50), left: pxDim(50)))
                }
                .theme(.dark)
                .disabled(disabled)
            }
            .alignItems(.flexStart)
        }
        window.drawFrameIfNeeded()
        let scene = window.lastScene
        let subject = try rect(scene, 30, 30)
        try #require(subject.bounds.origin.x == 50 && subject.bounds.origin.y == 50,
                     "\(authority): the presentation at the window's (50, 50)")
        let hitIndex = topmostOpaqueHitbox(in: window.lastHitboxes, at: pt(65, 65))
        let hit = hitIndex.map { window.lastHitboxes[$0].bounds == bounds(50, 50, 30, 30) } ?? false
        click(platform, at: pt(65, 65))
        // The id, structurally: root → Row (0) → the scope is transparent, so the
        // `Deferred` is the Row's child 1 → its content at 0.
        let row = GlobalElementID.child(of: GlobalElementID.child(of: nil, at: 0, name: nil), at: 0, name: nil)
        let id = GlobalElementID.child(of: GlobalElementID.child(of: row, at: 1, name: nil), at: 0, name: nil)
        window.focus(id)
        redraw(window)
        return (log.names.count, window.focusedElement == id, hit,
                hsla(subject.background), hsla(try rect(scene, 11, 10).background))
    }
    try #require(Theme.dark.surface != Theme.light.surface)
    let control = try run(disabled: false)
    #expect(control.colour == Theme.dark.surface, "\(authority): the presentation reads its scope's dark theme")
    #expect(control.outside == Theme.light.surface, "\(authority): control — the sibling outside the scope is light")
    #expect(control.hit && control.clicks == 1 && control.focused,
            "\(authority): control — hit \(control.hit), clicks \(control.clicks), focused \(control.focused)")
    let disabled = try run(disabled: true)
    #expect(!disabled.hit && disabled.clicks == 0 && !disabled.focused,
            "\(authority): a disabled scope reaches the presentation — hit \(disabled.hit), clicks \(disabled.clicks), focused \(disabled.focused)")
    #expect(disabled.colour == Theme.dark.surface, "\(authority): and the theme still does")
}

// MARK: - 3.4 The accessibility record and focus

/// **3.4** (`AB-V`, `AB-W`, `AB-J`). The demo-shaped scrim — `inset(0)`, `auto`
/// size, labelled "Close modal" — publishes a button at the **whole window**, on
/// layer 1, as a root of the tree; the card inside it is focusable, focus moved to
/// it survives the next frame, and a key reaches it.
///
/// Mutation that must redden it: **M1c** (W not aliased: the record's geometry
/// shrinks to the card-sized stack).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aPresentationsAccessibilityRecordAndFocusMatchUnderBothAuthorities(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let log = Log()
    let (window, platform) = try presentationWindow(authority) {
        Row {
            Box().width(px(50)).height(px(50)).background(.surface)
            Deferred {
                Stack(alignment: .center) {
                    Box().width(px(40)).height(px(30)).background(.surface)
                        .focusable().onClick {}
                        .onKey { _ in log.names.append("card"); return true }
                }
                .position(.absolute)
                .inset(px(0))
                .background(.scrim)
                .onClick {}
                .accessibilityLabel("Close modal")
            }
        }
        .alignItems(.flexStart)
    }
    platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let (scrimID, scrim) = try #require(tree.nodes.first { $0.value.label == "Close modal" },
                                        "\(authority): the scrim publishes its label")
    #expect(scrim.role == .button, "\(authority): a button (AB-G)")
    #expect(tree.roots.contains(scrimID), "\(authority): portal content is a root (AB-V)")
    let geometry = try #require(tree.geometry[scrimID])
    #expect(geometry.frame == bounds(0, 0, 200, 200) && geometry.layer == 1,
            "\(authority): at the whole window on layer 1; got \(geometry.frame) layer \(geometry.layer)")

    let cardIndex = try #require(topmostOpaqueHitbox(in: window.lastHitboxes, at: pt(100, 100)))
    let card = window.lastHitboxes[cardIndex]
    try #require(card.bounds == bounds(80, 85, 40, 30), "\(authority): the card centred; got \(card.bounds)")
    #expect(window.lastFocusRegistry.isFocusable(card.id), "\(authority): the card is focusable")
    window.focus(card.id)
    redraw(window)
    #expect(window.focusedElement == card.id, "\(authority): focus survives the next frame")
    platform.simulateInput(keyDown("x"))
    #expect(log.names == ["card"], "\(authority): a key reaches the focused presentation")
}

// MARK: - 3.5 An animated inset

@Observable
private final class InsetModel {
    var top: Float = 10
}

/// **3.5** (`AN-`, `LR-AS`). `withAnimation(.linear(duration: 1))` moves a
/// presentation's `top` from 10 to 50; at half the duration its y is **30** under
/// both authorities — the lowering reads which insets are given from the declared
/// style and their LENGTHS from the animated one (`LR-CI`). **Linear, named**
/// (`LR-CP` item 3): `withAnimation`'s default is a spring whose half-way value is
/// not 30. Pre-flighted in both end states.
///
/// Mutation that must redden it: **M3c** (`lowerPresentation` reads the declared
/// insets: the proposal arm reads 50 mid-flight) — lane 1's X1, handed here.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func anAnimatedInsetInterpolatesItsValueUnderBothAuthorities(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    @MainActor func tree(_ top: Float) -> some Element {
        Row {
            Box().width(px(10)).height(px(10)).background(.surface)
            Deferred {
                Box().width(px(20)).height(px(20)).background(.accent)
                    .position(.absolute).inset(edges(top: pxDim(top), left: pxDim(30)))
            }
        }
        .alignItems(.flexStart)
    }
    let end = LayoutDifferential.compare(width: 200, height: 200) { tree(50) }
    try #require(end.unlowerable.isEmpty, "the end state: \(end.unlowerable)")
    let model = InsetModel()
    let (window, platform) = try presentationWindow(authority, startsDisplayLink: true) { tree(model.top) }
    func y() throws -> Float { try rect(window.lastScene, 20, 20).bounds.origin.y }

    platform.simulateTick(timestamp: 100)
    try #require(try y() == 10, "\(authority): set up — the resting baseline is 10")
    withAnimation(.linear(duration: 1)) { model.top = 50 }
    platform.simulateTick(timestamp: 100)
    #expect(try y() == 10, "\(authority): the frame that starts the transition reads `from`")
    platform.simulateTick(timestamp: 100.5)
    let mid = try y()
    try #require(mid != 10 && mid != 50,
                 "\(authority): mid-flight must differ from both endpoints; got \(mid) (snapped)")
    #expect(mid == 30, "\(authority): half of linear(1) from 10 to 50 is 30; got \(mid)")
    platform.simulateTick(timestamp: 101)
    #expect(try y() == 50, "\(authority): lands on the target")
}

// MARK: - 3.6 Nested presentations on one layer (AP-H)

/// **3.6** (`AP-H`, `LR-CL`). A tooltip presentation declared inside the
/// demo-shaped `inset(0)` scrim: both land on layer 1 (one hoist, not a stack of
/// stacking contexts), nothing is reported — the scrim covers the window, so the
/// tooltip's legacy containing block (the scrim's padding box) is the window — the
/// tooltip sits at the window's (5, 5) and paints after the scrim, and its hitbox
/// outranks the scrim's there.
///
/// Mutation that must redden it: **M3d** (`pushLayer` pushes `activeLayer +
/// rootLayer`: the tooltip lands on layer 2; both authorities).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func nestedPresentationsLandOnOneLayerUnderBothAuthorities(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let (window, _) = try presentationWindow(authority) {
        Row {
            Box().width(px(50)).height(px(50)).background(.surface)
            Deferred {
                Stack(alignment: .center) {
                    Box().width(px(40)).height(px(30)).background(.surface)
                    Deferred {
                        Box().width(px(10)).height(px(10)).background(.accent).onClick {}
                            .position(.absolute).inset(edges(top: pxDim(5), left: pxDim(5)))
                    }
                }
                .position(.absolute)
                .inset(px(0))
                .background(.scrim)
                .onClick {}
            }
        }
        .alignItems(.flexStart)
    }
    window.drawFrameIfNeeded()
    let hitboxes = window.lastHitboxes
    let scrim = try #require(hitboxes.first { $0.bounds == bounds(0, 0, 200, 200) }, "\(authority): the scrim's hitbox")
    let tooltip = try #require(hitboxes.first { $0.bounds == bounds(5, 5, 10, 10) },
                               "\(authority): the tooltip's hitbox at the window's (5, 5)")
    #expect(scrim.layer == 1 && tooltip.layer == 1,
            "\(authority): both on the root layer — scrim \(scrim.layer), tooltip \(tooltip.layer)")
    let top = try #require(topmostOpaqueHitbox(in: hitboxes, at: pt(10, 10)))
    #expect(hitboxes[top].id == tooltip.id, "\(authority): the tooltip outranks the scrim over itself")
    let rects = window.lastScene.rects
    let scrimRect = try #require(rects.firstIndex { $0.bounds.size.width == 200 && $0.bounds.size.height == 200 })
    let tipRect = try #require(rects.firstIndex { $0.bounds.size.width == 10 && $0.bounds.size.height == 10 })
    #expect(tipRect > scrimRect, "\(authority): the tooltip paints after the scrim")
}
