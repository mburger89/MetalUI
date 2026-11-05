import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Key and focus scoping, lane A — focus on press and the no-resign rule
// (rulings `KF-F`, `KF-G`, `KF-E` item 5; spec §4.3, tests A25–A33). SwiftUI's
// answers are the probe `docs/probes/swiftui-key-focus.swift` arms FC1–FC7
// and RS1–RS5.
//
// Windows are 200 × 200 over `FakePlatformWindow`, roots centred (`CN-J`).
// Focus is read right after the press, before any frame, so a stage that
// focuses something the next frame would clear is still seen.

// MARK: - Harness

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func down(_ p: Point<Pixels>) -> InputEvent { .mouseDown(MouseEvent(position: p)) }
private func up(_ p: Point<Pixels>) -> InputEvent { .mouseUp(MouseEvent(position: p)) }
private func drag(_ p: Point<Pixels>) -> InputEvent { .mouseDragged(MouseEvent(position: p)) }

@MainActor private final class FPLog {
    var log: [String] = []
    var text = "abc"
}

@MainActor private func fpWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    window.drawFrameIfNeeded()
    // FC-E: the first draw seats the first focusable; these tests read what a PRESS focuses, from nothing.
    window.clearTheFirstDrawSeat()
    return (window, platform)
}

@MainActor private func click(_ platform: FakePlatformWindow, _ p: Point<Pixels>) {
    platform.simulateInput(down(p))
    platform.simulateInput(up(p))
}

/// A `size`-square box.
@MainActor private func square(_ size: Float) -> some StyledElement {
    Box().frame(width: px(size), height: px(size))
}

// MARK: - A25–A29

/// **A25** (FC3, `KF-F` item 2). A press focuses a `.focusable(interactions:
/// .edit)` element. Red before: the stub registers no press region (not
/// focused). Mutation: delete the `focusOnPress` call.
@MainActor
@Test func aPressFocusesAnEditInteractionFocusable() throws {
    let (window, platform) = try fpWindow { square(100).focusable(interactions: .edit) }
    let id = try #require(window.lastFocusRegistry.tabOrder.first)
    platform.simulateInput(down(pt(100, 100)))
    #expect(window.focusedElement == id, "the press focused the surface (FC3)")
}

/// **A26** (FC1, FC2, FC5; was "neither a plain `.focusable()` nor an
/// `.activate` one", divergence 94, retired by `FC-A`). A press focuses a plain
/// `.focusable()` and an explicit `.automatic` one (SwiftUI's click focus, FC1);
/// it focuses neither an `.activate` one (FC2) nor a `.focusable(false,
/// interactions: .edit)` one (FC5). Mutations: drop `.automatic` from the
/// predicate (the first two redden); treat `nil` as automatic (A26c).
@MainActor
@Test func aPressFocusesPlainAndAutomaticFocusablesButNotActivateOrDisabledOnes() throws {
    let (window, platform) = try fpWindow {
        HStack(spacing: 0) {
            square(50).focusable()
            square(50).focusable(interactions: .activate)
            square(50).focusable(interactions: .automatic)
            square(50).focusable(false, interactions: .edit)
        }
    }
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count == 3, "set up: three are focusable")
    // The plain one, then the activate one (focus stays on the plain one), then the
    // automatic one, then the non-focusable one (focus stays on the automatic one).
    platform.simulateInput(down(pt(25, 100)))
    #expect(window.focusedElement == order[0], "a plain .focusable() takes the press (FC1)")
    platform.simulateInput(down(pt(75, 100)))
    #expect(window.focusedElement == order[0], ".activate takes no press (FC2): focus stays")
    platform.simulateInput(down(pt(125, 100)))
    #expect(window.focusedElement == order[2], ".automatic takes the press (FC1)")
    platform.simulateInput(down(pt(175, 100)))
    #expect(window.focusedElement == order[2], "focusable(false, .edit) takes no press (FC5): focus stays")
}

/// **A26c** (`C1`, `C3`, `C4`, FKA off). A `Button`, `Toggle` and `Slider` are
/// Tab stops a click does not focus: a control sets `isFocusable` and records
/// no interactions, and `nil` interactions stay out of `focusesOnPress`
/// (`FC-A` item 2). Each click lands (its action runs: `C1` `tap`, `C3` `on=`,
/// `C4` `v=`), and focus stays on a focusable beside them (the separating
/// arm: `focus` is not merely unset). Mutation: treat `nil` as `.automatic`.
@MainActor
@Test func aPressOnAControlTakesNoFocus() throws {
    let m = FPLog()
    var on = false
    var value: Double = 0
    let (window, platform) = try fpWindow {
        VStack(spacing: 0) {
            square(40).focusable()
            Button("B") { m.log.append("tap") }.frame(width: px(200), height: px(40))
            Toggle("T", isOn: Binding(get: { on }, set: { on = $0; m.log.append("on=\($0)") }))
                .frame(width: px(200), height: px(40))
            Slider(value: Binding(get: { value }, set: { value = $0; m.log.append("v") }), in: 0...1)
                .frame(width: px(200), height: px(40))
        }
    }
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count == 4, "set up: the focusable, the button, the toggle and the slider are Tab stops: \(order)")
    let focusable = order[0]
    click(platform, pt(100, 20))
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == focusable, "set up: the plain focusable took the press")
    let buttonBounds = try #require(window.lastHitboxes.first { $0.id == order[1] && $0.opaque }).bounds
    let toggleBounds = try #require(window.lastHitboxes.first { $0.id == order[2] && $0.opaque }).bounds
    let sliderBounds = try #require(window.lastHitboxes.first { $0.id == order[3] }).bounds
    click(platform, centreOf(buttonBounds))
    #expect(window.focusedElement == focusable, "a Button click focuses nothing (C1)")
    click(platform, centreOf(toggleBounds))
    #expect(window.focusedElement == focusable, "a Toggle click focuses nothing (C3)")
    click(platform, Point(x: px(sliderBounds.origin.x.value + 30),
                          y: px(sliderBounds.origin.y.value + sliderBounds.size.height.value / 2)))
    #expect(window.focusedElement == focusable, "a Slider press focuses nothing (C4)")
    #expect(m.log.first == "tap" && m.log.contains("on=true") && m.log.contains("v"),
            "control: each control's own action ran (the clicks landed): \(m.log)")
}

/// **A26h** (`FC-A` item 2). The predicate itself: `focusesOnPress` is a
/// focusable whose interactions contain `.edit` or `.automatic`; absent
/// interactions (a control's, even with a keyboard attachment from an
/// `onKeyPress`), `.activate`, an empty set and `isFocusable == false` are out.
/// Mutations: drop `.automatic` (the `.automatic` row reddens); treat `nil` as
/// `.automatic` (the `nil` row reddens, and with it only this test and a demo
/// whose first press-focusable lookup finds a text field).
@MainActor
@Test func focusesOnPressFollowsTheInteractionsAndNotTheirAbsence() {
    func handlers(focusable: Bool = true, _ interactions: FocusInteractions?) -> Handlers {
        var h = Handlers()
        h.isFocusable = focusable
        h.keyboard = KeyboardAttachment.make(
            keyPresses: [KeyPressHandler(phases: [.down], filter: .any, action: { _ in .ignored })],
            focusInteractions: interactions, isKeyRegion: false, resignsOnPress: false, clipboard: nil)
        return h
    }
    #expect(handlers(.automatic).focusesOnPress, ".automatic is SwiftUI's click focus (FC1)")
    #expect(handlers(.edit).focusesOnPress, ".edit is FC3")
    #expect(handlers([.edit, .activate]).focusesOnPress, "a set holding .edit focuses")
    #expect(!handlers(nil).focusesOnPress, "absent interactions are a control's: Tab only (C1, C3, C4)")
    #expect(!handlers(.activate).focusesOnPress, ".activate is Tab only (FC2)")
    #expect(!handlers([]).focusesOnPress, "an empty set focuses nothing")
    #expect(!handlers(focusable: false, .automatic).focusesOnPress, "not focusable: nothing to focus (FC5)")
    #expect(!Handlers().focusesOnPress, "no keyboard attachment at all")
}

/// **A26i** (`C9` on the proposal path, `KF-H`; `FC-A` item 2's two other
/// spellings). A SwiftUI-vocabulary view's `.focusable()` wraps once in a
/// `KeyboardModifier` and a chained `.onKeyPress { }.focusable()` writes the
/// layer directly: both record `.automatic`, so both take a press; the
/// `.activate` spelling on either takes none. Mutations: leave `nil` at the
/// proposal wrapper (first arm), at the layer (both arms).
@MainActor
@Test func theProposalPathSpellingsOfFocusableTakeAPress() throws {
    let (window, platform) = try fpWindow {
        HStack(spacing: 0) {
            Rectangle(width: px(50), height: px(50)).focusable()
            Rectangle(width: px(50), height: px(50)).onKeyPress { _ in .ignored }.focusable()
            Rectangle(width: px(50), height: px(50)).focusable(interactions: .activate)
            Rectangle(width: px(50), height: px(50)).onKeyPress { _ in .ignored }
                .focusable(interactions: .activate)
        }
    }
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count == 4, "set up: four proposal-path focusables: \(order)")
    platform.simulateInput(down(pt(25, 100)))
    #expect(window.focusedElement == order[0], "wrapper spelling: .focusable() takes the press")
    platform.simulateInput(down(pt(75, 100)))
    #expect(window.focusedElement == order[1], "layer spelling: .onKeyPress { }.focusable() takes the press")
    platform.simulateInput(down(pt(125, 100)))
    #expect(window.focusedElement == order[1], ".activate takes none: focus stays")
    platform.simulateInput(down(pt(175, 100)))
    #expect(window.focusedElement == order[1], "nor does the layer's .activate")
}

/// **A26d** (`C6`). Clicking a `Button` leaves a focused view focused. The
/// focus was taken by a press (a plain focusable), not set from code.
@MainActor
@Test func clickingAButtonKeepsTheCurrentFocus() throws {
    let m = FPLog()
    let (window, platform) = try fpWindow {
        VStack(spacing: 0) {
            square(100).focusable()
            Button("B") { m.log.append("tap") }.frame(width: px(200), height: px(60))
        }
    }
    let focusable = try #require(window.lastFocusRegistry.tabOrder.first)
    click(platform, pt(100, 30))
    try #require(window.focusedElement == focusable, "set up: the press focused the focusable")
    click(platform, pt(100, 160))
    #expect(m.log == ["tap"], "the button's click ran: \(m.log)")
    #expect(window.focusedElement == focusable, "and focus stayed (C6)")
}

/// **A26e** (`C7`, `C7b`, `C7c` against divergence 57, `C13`, `C16`). A
/// focusable BENEATH a tappable keeps focus where it was and the tap runs
/// (`C7`, aligned: the tappable's opaque hitbox is the cover and the focusable
/// is not its ancestor). Beneath a plain `Color` it **focuses** (`C7b`,
/// divergence 57: a plain colour is no pointer target here, SwiftUI's covers
/// the press). A focusable ABOVE a tappable focuses (`C7c`) and the tap behind
/// **still fires** (divergence 57: SwiftUI's does not; the press region is
/// non-opaque). `C13`: a `Button.focusable()` focuses (the outer box, the
/// button itself stays a control) and its click runs; `C16`: a `Button` inside
/// a focusable container focuses the container and the click runs.
@MainActor
@Test func aFocusableCoveredByOrCoveringAnotherElementStillTakesThePress() throws {
    let m = FPLog()
    // C7: the tappable above the focusable.
    do {
        let (window, platform) = try fpWindow {
            ZStack {
                square(100).focusable()
                square(100).onTapGesture { m.log.append("tap") }
            }
        }
        let id = try #require(window.lastFocusRegistry.tabOrder.first)
        click(platform, pt(100, 100))
        _ = id
        #expect(m.log == ["tap"], "C7: the covering tappable ran")
        #expect(window.focusedElement == nil, "C7 (aligned): the cover keeps focus where it was, so the focusable beneath is not focused")
        m.log = []
    }
    // C7b: a plain Color above the focusable.
    do {
        let (window, platform) = try fpWindow {
            ZStack { square(100).focusable(); Color.red.frame(width: px(100), height: px(100)) }
        }
        let id = try #require(window.lastFocusRegistry.tabOrder.first)
        click(platform, pt(100, 100))
        #expect(window.focusedElement == id, "C7b (differs, divergence 57): the plain colour is no pointer target")
    }
    // C7c: the focusable above a tappable.
    do {
        let (window, platform) = try fpWindow {
            ZStack {
                square(100).onTapGesture { m.log.append("tap") }
                square(100).focusable()
            }
        }
        let id = try #require(window.lastFocusRegistry.tabOrder.first)
        click(platform, pt(100, 100))
        #expect(window.focusedElement == id, "C7c: the focusable above the tappable focuses")
        #expect(m.log == ["tap"], "C7c (differs, divergence 57): the tap behind still fires")
        m.log = []
    }
    // C13: Button.focusable().
    do {
        let (window, platform) = try fpWindow {
            Button("B") { m.log.append("tap") }.frame(width: px(100), height: px(100)).focusable()
        }
        let id = try #require(window.lastFocusRegistry.tabOrder.first, "the outer focusable box")
        click(platform, pt(100, 100))
        #expect(m.log == ["tap"], "C13: the button's click ran")
        #expect(window.focusedElement == id, "C13: and Button.focusable() took the press")
        m.log = []
    }
    // C16: a Button inside a focusable container.
    do {
        let (window, platform) = try fpWindow {
            Column { Button("B") { m.log.append("tap") }.frame(width: px(100), height: px(100)) }
                .frame(width: px(200), height: px(200)).focusable()
        }
        let container = try #require(window.lastFocusRegistry.tabOrder.first)
        let button = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil })
        click(platform, centreOf(button.bounds))
        #expect(m.log == ["tap"], "C16: the button's click ran")
        #expect(window.focusedElement == container, "C16: the container took the press")
    }
}

/// **A26f** (`C8a`, `C15`). Two sibling focusables: a press on the first
/// focuses it, a press on the second moves focus to it. Nested focusables: the
/// inner takes a press on it, the outer takes a press on its own margin.
/// Mutation: take the outermost member (reddens the inner reading).
@MainActor
@Test func siblingAndNestedFocusablesTakeTheirOwnPresses() throws {
    let (siblings, siblingsPlatform) = try fpWindow {
        HStack(spacing: 0) { square(100).focusable(); square(100).focusable() }
    }
    let pair = siblings.lastFocusRegistry.tabOrder
    try #require(pair.count == 2)
    click(siblingsPlatform, pt(50, 100))
    #expect(siblings.focusedElement == pair[0], "C15: the first")
    click(siblingsPlatform, pt(150, 100))
    #expect(siblings.focusedElement == pair[1], "C15: then the second")

    let (nested, nestedPlatform) = try fpWindow {
        square(40).focusable().frame(width: px(120), height: px(120)).focusable()
    }
    let chain = nested.lastFocusRegistry.tabOrder
    try #require(chain.count == 2, "set up: outer and inner")
    let inner = try #require(nested.lastHitboxes.first { $0.id != chain[0] && $0.handlers.keyboard != nil })
    click(nestedPlatform, centreOf(inner.bounds))
    #expect(nested.focusedElement == inner.id, "C8a: the inner takes a press on it")
    click(nestedPlatform, pt(100 - 55, 100))
    #expect(nested.focusedElement == chain[0], "C8a: the outer takes a press on its own margin")
}

/// **A26g** (`C10`, `C11`, `C12`, `C12b`). A right press, a `.disabled(true)`
/// focusable and a `.allowsHitTesting(false)` one (written on either side of
/// `.focusable()`) take no press, with a focusable beside them already focused
/// so a missing focus is a real answer (the probe's `T1`: a lone focusable
/// takes focus from any click).
@MainActor
@Test func aSecondaryPressADisabledAndAHitTestingOffFocusableTakeNoFocus() throws {
    let (window, platform) = try fpWindow {
        HStack(spacing: 0) {
            square(50).focusable()
            square(50).focusable()
            square(50).focusable().disabled(true)
            square(50).focusable().allowsHitTesting(false)
        }
    }
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count >= 2)
    click(platform, pt(25, 100))
    try #require(window.focusedElement == order[0], "set up: the first took the press")
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(75, 100))))
    platform.simulateInput(.rightMouseUp(MouseEvent(position: pt(75, 100))))
    #expect(window.focusedElement == order[0], "C10: a right press focuses nothing")
    click(platform, pt(125, 100))
    #expect(window.focusedElement == order[0], "C11: .disabled(true) takes no press")
    click(platform, pt(175, 100))
    #expect(window.focusedElement == order[0], "C12: .allowsHitTesting(false) takes no press")
    let (before, beforePlatform) = try fpWindow {
        HStack(spacing: 0) {
            square(50).focusable()
            square(50).allowsHitTesting(false).focusable()
        }
    }
    click(beforePlatform, pt(75, 100))
    let first = try #require(before.focusedElement, "set up: the first took the press")
    click(beforePlatform, pt(125, 100))
    #expect(before.focusedElement == first, "C12b: .allowsHitTesting(false) written before .focusable() takes no press")
}

/// **A27** (FC6). A press on a click-focusable element focuses it and still
/// taps and clicks it: the stage claims nothing. Red before: not focused.
/// Mutation: make `focusOnPress` claim the event.
@MainActor
@Test func aPressFocusesAndStillTaps() throws {
    let m = FPLog()
    let (window, platform) = try fpWindow {
        HStack(spacing: 0) {
            square(100).focusable(interactions: .edit).onTapGesture { m.log.append("tap") }
            square(100).focusable(interactions: .edit).onClick { m.log.append("click") }
        }
    }
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count == 2)
    click(platform, pt(50, 100))
    #expect(window.focusedElement == order[0], "focused by the press")
    click(platform, pt(150, 100))
    #expect(window.focusedElement == order[1], "focused by the press")
    #expect(m.log == ["tap", "click"], "and the press still tapped and clicked (FC6): \(m.log)")
}

/// **A28** (`KF-F` item 3). The innermost click-focusable element wins, and a
/// text field inside one takes focus itself. Red before: nothing focused.
/// Mutations: take the outermost member; skip step 1 (equivalent for the
/// field, `KF-X`: the text stage focuses it in the same event).
@MainActor
@Test func theInnermostClickFocusableWinsAndAFieldInsideTakesFocus() throws {
    let m = FPLog()
    let (window, platform) = try fpWindow {
        Column {
            square(60).focusable(interactions: .edit)
            TextField("t", text: m.text) { m.text = $0 }.frame(width: px(100), height: px(24))
        }
        .frame(width: px(200), height: px(200))
        .focusable(interactions: .edit)
    }
    let order = window.lastFocusRegistry.tabOrder
    try #require(order.count == 3, "set up: outer, inner, field: \(order)")
    let inner = try #require(window.lastHitboxes.first { $0.id == order[1] && $0.handlers.keyboard != nil })
    platform.simulateInput(down(Point(x: px(inner.bounds.origin.x.value + 30), y: px(inner.bounds.origin.y.value + 30))))
    #expect(window.focusedElement == order[1], "the inner surface, not the outer")
    let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    platform.simulateInput(down(Point(x: px(field.bounds.origin.x.value + 50), y: px(field.bounds.origin.y.value + 12))))
    #expect(window.focusedElement == field.id, "the field inside takes focus itself")
    platform.simulateInput(down(pt(5, 5)))
    #expect(window.focusedElement == order[0], "outside both inner members: the outer surface")
}

/// **A29** (`MN-B`, divergence 110). A secondary or other-button press focuses
/// nothing. Mutation: run the stage on `.rightMouseDown`.
@MainActor
@Test func aSecondaryPressFocusesNothing() throws {
    let (window, platform) = try fpWindow { square(100).focusable(interactions: .edit) }
    _ = try #require(window.lastFocusRegistry.tabOrder.first)
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(100, 100))))
    platform.simulateInput(.rightMouseUp(MouseEvent(position: pt(100, 100))))
    platform.simulateInput(.otherMouseDown(MouseEvent(position: pt(100, 100))))
    platform.simulateInput(.otherMouseUp(MouseEvent(position: pt(100, 100))))
    #expect(window.focusedElement == nil, "only a primary press focuses")
}

// MARK: - A30–A31: no resign (`KF-G`)

/// A focused field on top, and below it a plain box, a tap target, a `Button`
/// and a draggable, each 40 wide; `extra` is a fifth element.
@MainActor private func fieldAndTargets<E: Element>(_ m: FPLog, _ extra: E) -> some Element {
    Column {
        TextField("t", text: m.text) { m.text = $0 }.frame(width: px(200), height: px(24))
        Row {
            square(40)
            square(40).onTapGesture { m.log.append("tap") }
            Button("B") { m.log.append("button") }.frame(width: px(40), height: px(40))
            square(40).draggable("payload")
            extra
        }
    }
}

/// **A30** (RS1, RS2, RS3, RS5). A press on plain content, a tap target, a
/// `Button` or a drag source leaves a focused field focused — SwiftUI's
/// answer and MetalUI's at `c62d6ba` (green there, a pin). Mutation:
/// `focus(nil)` on every press outside a field.
@MainActor
@Test func aPressElsewhereDoesNotResignAFocusedField() throws {
    let m = FPLog()
    let (window, platform) = try fpWindow { fieldAndTargets(m, square(40)) }
    let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    click(platform, centreOf(field.bounds))
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == field.id, "set up: the field is focused")
    let rowY = field.bounds.origin.y.value + 24 + 20
    for x: Float in [20, 60, 100] {
        click(platform, pt(x, rowY))
        window.drawFrameIfNeeded()
        #expect(window.focusedElement == field.id, "a press at x \(x) left the field focused")
    }
    platform.simulateInput(down(pt(140, rowY)))
    platform.simulateInput(drag(pt(150, rowY + 10)))
    platform.simulateInput(up(pt(150, rowY + 10)))
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == field.id, "a drag left the field focused (RS5)")
    #expect(m.log == ["tap", "button"], "control: the targets ran: \(m.log)")
}

/// **A31** (RS4). A press on a click-focusable element moves focus from a
/// focused field. Red before: the field keeps focus. Mutation: delete §4.3's
/// step 2.
@MainActor
@Test func aClickFocusablePressMovesFocusFromAField() throws {
    let m = FPLog()
    let (window, platform) = try fpWindow { fieldAndTargets(m, square(40).focusable(interactions: .edit)) }
    let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil })
    click(platform, centreOf(field.bounds))
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == field.id, "set up: the field is focused")
    let surface = try #require(window.lastFocusRegistry.tabOrder.last, "the extra surface is last in Tab order")
    let rowY = field.bounds.origin.y.value + 24 + 20
    click(platform, pt(180, rowY))
    #expect(window.focusedElement == surface, "the click-focusable surface took focus (RS4)")
}

/// **A31b** (`KF-G`, `KF-E` item 5: the cover descends from the region). A
/// press on an opaque sibling drawn above a key region — an overlay button
/// over a canvas — changes no focus, and the click still lands; a press on
/// the region beside it clears focus (the control). Mutation V4: drop
/// `cover.id.isOrDescends(from: box.id)` in `focusOnPress`.
@MainActor
@Test func aPressOnAnOpaqueSiblingAboveAKeyRegionChangesNoFocus() throws {
    let m = FPLog()
    let (window, platform) = try fpWindow {
        VStack {
            ZStack {
                Box().frame(width: px(200), height: px(150)).hoverKeyRegion()
                square(40).onClick { m.log.append("click") }
            }
            square(20).focusable()
        }
    }
    let focusable = try #require(window.lastFocusRegistry.tabOrder.first)
    let button = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil })
    let region = try #require(window.lastHitboxes.first { $0.handlers.keyboard?.isKeyRegion == true })
    window.focus(focusable)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == focusable, "set up: focused")
    click(platform, centreOf(button.bounds))
    #expect(m.log == ["click"], "the click landed: \(m.log)")
    #expect(window.focusedElement == focusable, "a press on the sibling above the region kept focus")
    let corner = Point(x: px(region.bounds.origin.x.value + 5), y: px(region.bounds.origin.y.value + 5))
    try #require(!button.contains(corner), "set up: the corner is off the button")
    click(platform, corner)
    #expect(window.focusedElement == nil, "control: a press on the region itself clears focus")
}

/// **A31c** (`KF-E` items 3 and 5: on the cover's layer). A press on a
/// popover declared inside a key region changes no focus: the popover's
/// content descends from the region and lies inside its bounds, but is on
/// another layer, so the press is not inside the region. Mutation V1′: drop `box.layer ==
/// cover.layer` in `focusOnPress`.
@MainActor
@Test func aPressOnAKeyRegionsOwnPopoverChangesNoFocus() throws {
    let m = FPLog()
    let (window, platform) = try fpWindow {
        Box {
            Column {
                square(20).focusable()
                square(20).popover(isPresented: .constant(true)) {
                    square(40).onClick { m.log.append("click") }
                }
            }
        }
        .frame(width: px(200), height: px(200))
        .hoverKeyRegion()
    }
    for _ in 0..<4 where window.needsRedraw { window.drawFrameIfNeeded() }
    let focusable = try #require(window.lastFocusRegistry.tabOrder.first)
    let region = try #require(window.lastHitboxes.first { $0.handlers.keyboard?.isKeyRegion == true })
    let popover = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil })
    try #require(popover.layer != region.layer && region.contains(centreOf(popover.bounds)),
                 "set up: the popover is on its own layer, inside the region's bounds")
    window.focus(focusable)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == focusable, "set up: focused")
    click(platform, centreOf(popover.bounds))
    #expect(m.log == ["click"], "the popover's click landed: \(m.log)")
    #expect(window.focusedElement == focusable, "a press on the region's own popover kept focus")
}

/// **A26b** (`focusable(_:)`, `focusable(_:interactions:)`). `false` makes an
/// element not focusable — Tab skips it — and a later call replaces an
/// earlier one; `focusable(false, interactions: .edit)` is not focused by a
/// press. Mutation V9: `$0.isFocusable = true` regardless of the argument
/// (each overload separately).
@MainActor
@Test func focusableFalseRegistersNoFocusableAndALaterCallReplacesAnEarlierOne() throws {
    let (window, platform) = try fpWindow {
        HStack(spacing: 0) {
            square(40).focusable(false)
            square(40).focusable(true).focusable(false)
            square(40).focusable(false).focusable(true)
            square(40).focusable(false, interactions: .edit)
            square(40).focusable(interactions: .edit).focusable(false, interactions: .edit)
        }
    }
    let order = window.lastFocusRegistry.tabOrder
    #expect(order.count == 1, "only the box whose last call is focusable(true): \(order)")
    for x: Float in [140, 180] {
        platform.simulateInput(down(pt(x, 100)))
        platform.simulateInput(up(pt(x, 100)))
        #expect(window.focusedElement == nil, "a press at x \(x) on focusable(false, .edit) focused nothing")
    }
    window.focus(nil)
    platform.simulateInput(.keyDown(KeyEvent(charactersIgnoringModifiers: "\t", characters: "\t", timestamp: 0)))
    #expect(window.focusedElement == order.first, "Tab reaches only the focusable box")
}

private func centreOf(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: px(b.origin.x.value + b.size.width.value / 2), y: px(b.origin.y.value + b.size.height.value / 2))
}

// MARK: - A32–A33: inert to every other pointer outcome, gated

/// The A32 tree: a 200-square base with a click, a hover callback, a wheel
/// handler and a drop destination, a tap target in its corner, and over the
/// whole of it a transparent 200-square box, optionally a click-focusable key
/// region.
@MainActor private func a32Tree(_ m: FPLog, regions: Bool, plain: Bool = false) -> some Element {
    let cover = square(200)
    return ZStack {
        square(200)
            .onClick { m.log.append("click") }
            .onHover { m.log.append("hover \($0)") }
            .onScrollWheel { _ in m.log.append("wheel"); return true }
            .dropDestination(for: String.self) { items, _ in m.log.append("drop \(items)"); return true }
        square(30).onTapGesture { m.log.append("tap") }
        if regions {
            // `plain`: a bare `.focusable()` cover (`FC-A`), no key region.
            if plain { cover.focusable() } else { cover.focusable(interactions: .edit).hoverKeyRegion() }
        } else { cover }
    }
}

/// Drives the A32 script and returns the log.
@MainActor private func a32Script(regions: Bool, plain: Bool = false) throws -> [String] {
    let m = FPLog()
    let (window, platform) = try fpWindow { a32Tree(m, regions: regions, plain: plain) }
    if regions {
        try #require(window.lastHitboxes.contains {
            plain ? $0.handlers.focusesOnPress : $0.handlers.keyboard?.isKeyRegion == true
        }, "set up: the region arm registers its region")
    }
    platform.simulateInput(.mouseMoved(MouseEvent(position: pt(50, 50))))
    click(platform, pt(50, 50))
    click(platform, pt(100, 100))
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(50, 50), delta: Point(x: px(0), y: px(5)))))
    let utf8 = PasteboardType(identifier: "public.utf8-plain-text",
                              conformsTo: ["public.plain-text", "public.text", "public.data", "public.item"])
    let item = DropItem(types: [utf8]) { _ in Array("x".utf8) }
    _ = platform.simulateDrop(.entered(position: pt(50, 50), items: [item]))
    _ = platform.simulateDrop(.performed(position: pt(50, 50), items: [item]))
    platform.simulateInput(.pointerExited)
    return m.log
}

/// **A32** (`KF-E` item 2, `KF-F` item 3). A click-focusable key region over a
/// base changes no other pointer outcome: the click, the hover set, the tap
/// arena, the wheel and the drop are identical with and without it. Red
/// before: the stub's region arm registers no region (the `#require`).
/// Mutation: register the region hitbox `opaque: true`.
@MainActor
@Test func pressAndKeyRegionsChangeNoOtherPointerOutcome() throws {
    let without = try a32Script(regions: false)
    try #require(without.contains("click") && without.contains("tap") && without.contains("wheel")
                    && without.contains { $0.hasPrefix("drop") } && without.contains("hover true"),
                 "control: every outcome happens without the region: \(without)")
    let with = try a32Script(regions: true)
    #expect(with == without, "identical with the region: \(with) vs \(without)")
}

/// **A32b** (`FC-A`). A bare `.focusable()` cover over the same base changes no
/// other pointer outcome either: it blocks no click, hover, tap, wheel or drop
/// aimed at what it covers (the press region is non-opaque). Mutation: register
/// the region hitbox `opaque: true`.
@MainActor
@Test func aPlainFocusableCoverChangesNoOtherPointerOutcome() throws {
    let without = try a32Script(regions: false)
    try #require(without.contains("click") && without.contains("tap") && without.contains("wheel")
                    && without.contains { $0.hasPrefix("drop") } && without.contains("hover true"),
                 "control: every outcome happens without the cover: \(without)")
    let with = try a32Script(regions: true, plain: true)
    #expect(with == without, "identical with a plain focusable cover: \(with) vs \(without)")
}

/// **A33** (`KF-E` item 2, `KF-F` item 3). `.disabled(true)`, `.hidden()` and
/// `.allowsHitTesting(false)` withdraw the press region and the key region:
/// a press focuses nothing (read before any frame) and a hovered key reaches
/// nothing. Red before: vacuous — the stub registers nothing (green); the
/// mutation registers outside the gates.
@MainActor
@Test func disabledHiddenAndAllowsHitTestingWithdrawThePressAndKeyRegions() throws {
    for gate in ["disabled", "hidden", "allowsHitTesting"] {
        let m = FPLog()
        let (window, platform) = try fpWindow {
            HStack(spacing: 0) {
                let surface = square(100).focusable(interactions: .edit).hoverKeyRegion()
                    .onKeyPress { _ in m.log.append("key"); return .handled }
                switch gate {
                case "disabled": surface.disabled(true)
                case "hidden": surface.hidden()
                default: surface.allowsHitTesting(false)
                }
                square(100).focusable(interactions: .edit)
            }
        }
        _ = try #require(window.lastHitboxes.first { $0.handlers.keyboard != nil },
                         "control (\(gate)): the ungated sibling registers its press region")
        #expect(window.lastHitboxes.filter { $0.handlers.keyboard != nil }.count == 1,
                "\(gate): only the sibling's region")
        platform.simulateInput(down(pt(50, 100)))
        #expect(window.focusedElement == nil, "\(gate): the press focused nothing")
        platform.simulateInput(up(pt(50, 100)))
        platform.simulateInput(.mouseMoved(MouseEvent(position: pt(50, 100))))
        platform.simulateInput(.keyDown(KeyEvent(charactersIgnoringModifiers: "x", characters: "x", timestamp: 0)))
        #expect(m.log.isEmpty, "\(gate): no key reached the withdrawn region: \(m.log)")
    }
}
