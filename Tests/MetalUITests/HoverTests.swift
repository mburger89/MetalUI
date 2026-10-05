import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// `onHover` and `onContinuousHover`, lane 2, tests 2.43–2.57 (rulings `SV-N`,
// `SV-Z`, `SV-U`; spec §6.2). SwiftUI's hover is unmeasured (probe arms `H1`–
// `H11` read `[]` under both instruments — a broken instrument in an inactive
// app), so every rule here is MetalUI's own, ruled against gpui's model;
// human check U8 looks at it.
//
// Windows are 200 × 200 over `FakePlatformWindow`, roots centred (`CN-J`): a
// 40 × 40 tile spans 80…120 on both axes. Pointer events are delivered with
// `simulateInput`; the after-frame recompute runs inside
// `drawFrameIfNeeded()`. Nothing sleeps. Red before: the file does not
// compile at `3aa9898` (no `onHover`, `onContinuousHover`, `HoverPhase`).

// MARK: - Harness

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func mv(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }
private func key(_ c: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: [], timestamp: 0))
}

@Observable @MainActor final class HVModel {
    var log: [String] = []
    var shown = true
    var dx: Float = 0
}

@MainActor private func hvWindow<Root: Element>(native: Bool = true,
                                                _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    platform.presentsMenusNatively = native
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// The hover regions of the last frame.
@MainActor private func hoverRegions(_ window: Window) -> [Hitbox] {
    window.lastHitboxes.filter { $0.handlers.hover != nil }
}

@MainActor private func tile(_ m: HVModel, _ name: String, _ w: Float = 40, _ h: Float = 40) -> some StyledElement {
    Box().frame(width: px(w), height: px(h)).background(.accent)
        .onHover { m.log.append("\(name) \($0)") }
}

/// A component whose `onHover` writes its own `@State`, read back through the
/// width of its 7-tall bar: 10 + 10 per enter.
private struct HVCounter: Component {
    @State var enters = 0
    var content: some ElementGroup {
        Box().frame(width: px(10 + 10 * Float(enters)), height: px(7)).background(.accent)
            .onHover { if $0 { enters += 1 } }
    }
}

@MainActor private func width(_ window: Window, height: Float) -> Float? {
    let matches = window.lastScene.rects.filter { $0.bounds.size.height == height }
    return matches.count == 1 ? matches[0].bounds.size.width : nil
}

// MARK: - 2.43–2.47: enter, leave, nesting, covers, gates

/// **2.43** (`SV-N` items 1, 4). Out → in → within → out fires `[true,
/// false]`, from input; a move within fires nothing; an `@State` write in the
/// callback lands (it runs under the element's dispatch). Mutation: fire on
/// every move.
@MainActor
@Test func onHoverFiresOnEnterAndLeaveFromInput() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow { Column { tile(m, "t") } }
    try #require(hoverRegions(window).count == 1)
    platform.simulateInput(mv(5, 5))
    platform.simulateInput(mv(100, 100))
    #expect(m.log == ["t true"], "the enter fires from input, before any frame")
    platform.simulateInput(mv(101, 102))
    platform.simulateInput(mv(195, 195))
    #expect(m.log == ["t true", "t false"])

    let (counter, counterPlatform) = try hvWindow { HVCounter() }
    let region = try #require(hoverRegions(counter).first)
    let inside = pt(region.bounds.origin.x.value + 2, region.bounds.origin.y.value + 2)
    counterPlatform.simulateInput(.mouseMoved(MouseEvent(position: inside)))
    counter.drawFrameIfNeeded()
    #expect(width(counter, height: 7) == 20, "the callback's @State write lands")
    withExtendedLifetime((window, counter)) {}
}

/// **2.44** (`SV-N` items 3, 5). Nested regions both hover: entering goes
/// outermost first, leaving innermost first. Mutation: reverse either order.
@MainActor
@Test func nestedHoverRegionsAllHoverEnteringOuterFirstLeavingInnerFirst() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow {
        Box { tile(m, "inner") }
            .frame(width: px(100), height: px(100))
            .onHover { m.log.append("outer \($0)") }
    }
    try #require(hoverRegions(window).count == 2)
    platform.simulateInput(mv(2, 2))
    platform.simulateInput(mv(100, 100))
    platform.simulateInput(mv(198, 198))
    #expect(m.log == ["outer true", "inner true", "inner false", "outer false"])
    withExtendedLifetime(window) {}
}

/// **2.45** (`SV-N` item 3, divergence 114's rule). An opaque target drawn
/// over a hover region covers it; a cover that only paints, or carries only a
/// non-opaque region (a context menu), does not. Mutation: every hitbox is a
/// cover (the context-menu arm reads `false`).
@MainActor
@Test func anOpaqueTargetCoversHoverBeneathAndAPaintedCoverDoesNot() throws {
    @MainActor func under<Cover: Element & ProposalElement>(_ cover: Cover) throws -> [String] {
        let m = HVModel()
        let (window, platform) = try hvWindow {
            ZStack {
                Rectangle(width: px(100), height: px(100)).onHover { m.log.append("under \($0)") }
                cover
            }
        }
        platform.simulateInput(mv(100, 100))
        withExtendedLifetime(window) {}
        return m.log
    }
    #expect(try under(Rectangle(width: px(100), height: px(100)).onTapGesture {}) == [],
            "an opaque cover covers")
    #expect(try under(Rectangle(width: px(100), height: px(100))) == ["under true"],
            "a painted cover does not")
    #expect(try under(Rectangle(width: px(100), height: px(100)).contextMenu { Button("X") {} })
            == ["under true"], "a context menu's non-opaque region does not")
}

/// **2.46** (`SV-N` item 2, `H8`'s shape). A hover region drawn over a click
/// target never blocks its click. Mutation: register the region opaque.
@MainActor
@Test func aHoverRegionNeverBlocksAClickBeneath() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow {
        ZStack {
            Rectangle(width: px(100), height: px(100)).onTapGesture { m.log.append("tap") }
            Rectangle(width: px(100), height: px(100)).onHover { m.log.append("hover \($0)") }
        }
    }
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(100, 100))))
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(100, 100))))
    #expect(m.log.contains("tap"), "the click beneath fires: \(m.log)")
    #expect(m.log.contains("hover true"), "and the region above hovers: \(m.log)")
    withExtendedLifetime(window) {}
}

/// **2.47** (`SV-N` item 2). `.allowsHitTesting(false)` and `.disabled(true)`
/// withdraw the region: no callbacks, no region. Mutation: register outside
/// the gates.
@MainActor
@Test func allowsHitTestingFalseAndDisabledWithdrawTheRegion() throws {
    let m = HVModel()
    let (off, offPlatform) = try hvWindow { Column { tile(m, "off").allowsHitTesting(false) } }
    let (disabled, disabledPlatform) = try hvWindow { Column { tile(m, "disabled").disabled(true) } }
    let (control, controlPlatform) = try hvWindow { Column { tile(m, "control") } }
    for platform in [offPlatform, disabledPlatform, controlPlatform] { platform.simulateInput(mv(100, 100)) }
    #expect(hoverRegions(off).isEmpty && hoverRegions(disabled).isEmpty)
    #expect(m.log == ["control true"], "only the control hovers: \(m.log)")
    withExtendedLifetime((off, disabled, control)) {}
}

// MARK: - 2.48–2.53: transforms, layers, leaving

/// **2.48** (`SV-N` item 3, `GX-I`). A rotated element hovers where it is
/// drawn: a 160 × 20 bar turned 90° about its centre is hovered at (100, 40)
/// and not at (40, 100), where it was laid out. Mutation: test `bounds`
/// without the transform.
@MainActor
@Test func hoverFollowsARenderEffect() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow {
        Box().frame(width: px(160), height: px(20)).background(.accent)
            .onHover { m.log.append("bar \($0)") }
            .rotationEffect(.degrees(90))
    }
    platform.simulateInput(mv(40, 100))
    #expect(m.log.isEmpty, "the laid-out place is not hovered: \(m.log)")
    platform.simulateInput(mv(100, 40))
    #expect(m.log == ["bar true"])
    withExtendedLifetime(window) {}
}

/// **2.49** (`SV-N` item 3, `IX-Q`). An opaque target on a higher layer — a
/// `Deferred` inside the hovered element — covers the region beneath, although
/// it descends from it. Mutation: drop the same-layer clause.
@MainActor
@Test func aHigherLayerCoversHoverBeneath() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow {
        Box {
            Deferred { Box().frame(width: px(40), height: px(40)).onClick {} }
        }
        .frame(width: px(40), height: px(40))
        .onHover { m.log.append("under \($0)") }
    }
    try #require(window.lastHitboxes.contains { $0.opaque && $0.layer > 0 }, "set up: the cover is hoisted")
    platform.simulateInput(mv(100, 100))
    #expect(m.log.isEmpty, "a higher layer covers: \(m.log)")
    withExtendedLifetime(window) {}
}

/// **2.50** (`SV-N` item 7). `.pointerExited` ends hover — `onHover(false)`
/// from input — and un-sticks `lastMousePosition`, so the next frame paints
/// nothing hovered. Mutation: not clearing `lastMousePosition` (the hover
/// background still paints).
@MainActor
@Test func pointerExitedClearsHoverAndIsHovered() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow {
        Column {
            Box().frame(width: px(40), height: px(40)).background(.surface).hoverBackground(.accent)
                .onClick {}
                .onHover { m.log.append("t \($0)") }
        }
    }
    let accent = window.theme[.accent]
    func paintsAccent() -> Bool {
        window.lastScene.rects.contains {
            $0.bounds.size.width == 40 && $0.background.h == accent.h && $0.background.s == accent.s
                && $0.background.l == accent.l && $0.background.a == accent.a
        }
    }
    platform.simulateInput(mv(100, 100))
    window.drawFrameIfNeeded()
    try #require(paintsAccent(), "set up: the hovered box paints its hover background")
    platform.simulateInput(.pointerExited)
    #expect(m.log == ["t true", "t false"])
    #expect(window.lastMousePosition == nil)
    window.drawFrameIfNeeded()
    #expect(!paintsAccent(), "isHovered is false once the pointer left the window")
    withExtendedLifetime(window) {}
}

/// **2.51** (`SV-N` item 5). A hovered element that leaves the tree gets
/// `onHover(false)` once, after the frame it left in — through the last
/// frame's closure. Mutation: drop departed ids silently.
@MainActor
@Test func aHoveredElementThatLeavesGetsFalseAfterTheFrame() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow {
        Column {
            if m.shown { tile(m, "t") }
        }
    }
    platform.simulateInput(mv(100, 100))
    try #require(m.log == ["t true"])
    m.shown = false
    #expect(m.log == ["t true"], "nothing before the frame")
    window.drawFrameIfNeeded()
    #expect(m.log == ["t true", "t false"])
    psRedraw(window)
    #expect(m.log == ["t true", "t false"], "once")
    withExtendedLifetime(window) {}
}

/// **2.52** (`SV-N` item 4). Content moving under a still pointer hovers after
/// the frame, with no input event. Mutation: recompute only on input.
@MainActor
@Test func contentMovingUnderAStillPointerUpdatesHoverAfterTheFrame() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow {
        Column { tile(m, "t").offset(x: px(m.dx)) }
    }
    platform.simulateInput(mv(140, 100))
    try #require(m.log.isEmpty, "set up: the pointer starts beside the tile")
    m.dx = 40
    window.drawFrameIfNeeded()
    #expect(m.log == ["t true"])
    m.dx = 0
    window.drawFrameIfNeeded()
    #expect(m.log == ["t true", "t false"])
    withExtendedLifetime(window) {}
}

/// **2.53**, the menu half (`SV-N` item 6; the drawn alert's half is lane
/// 3's). While an in-window menu is open the hovered set is empty; when it
/// closes the region under the still pointer hovers again. Mutation: ignore
/// the menu.
@MainActor
@Test func anOpenInWindowMenuOrDrawnAlertEmptiesTheHoverSet() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow(native: false) {
        Column { tile(m, "t").contextMenu { Button("Copy") {} } }
    }
    platform.simulateInput(mv(100, 100))
    try #require(m.log == ["t true"])
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(100, 100))))
    platform.simulateInput(.rightMouseUp(MouseEvent(position: pt(100, 100))))
    try #require(window.menuSession != nil && window.menuSession?.isNative == false, "set up: in-window menu")
    window.drawFrameIfNeeded()
    #expect(m.log == ["t true", "t false"], "the open menu empties the set")
    platform.simulateInput(key("\u{1b}"))
    try #require(window.menuSession == nil)
    window.drawFrameIfNeeded()
    #expect(m.log == ["t true", "t false", "t true"], "closed: hovered again")
    withExtendedLifetime(window) {}
}

// MARK: - 2.54: continuous hover

/// **2.54** (`SV-N` items 1, 5). `onContinuousHover` reports `.active` with
/// the pointer in the element's own space — an `.offset` element's offset
/// subtracted — on every move inside, and `.ended` on leaving. Mutation:
/// report window points.
@MainActor
@Test func onContinuousHoverReportsLocalPointsAndEnded() throws {
    var phases: [HoverPhase] = []
    let (window, platform) = try hvWindow {
        Column {
            Box().frame(width: px(40), height: px(40)).background(.accent)
                .onContinuousHover { phases.append($0) }
                .offset(x: px(30))
        }
    }
    platform.simulateInput(mv(95, 100))
    #expect(phases.isEmpty, "the laid-out place is not hovered")
    platform.simulateInput(mv(115, 100))
    platform.simulateInput(mv(116, 101))
    platform.simulateInput(mv(190, 100))
    #expect(phases == [.active(pt(5, 20)), .active(pt(6, 21)), .ended])
    withExtendedLifetime(window) {}
}

// MARK: - 2.55–2.57: cost and covering siblings

/// **2.55** (`SV-N` item 2, `SV-U`). A tree with no hover modifier registers no
/// extra hitbox — its list is exactly its two click targets — and pointer
/// events do no hover work. Mutation: register a region for every element.
@MainActor
@Test func aTreeWithoutHoverRegistersNoRegionAndDoesNoHoverWork() throws {
    let (window, platform) = try hvWindow {
        Column {
            Box().frame(width: px(40), height: px(40)).onClick {}
            Box().frame(width: px(40), height: px(40))
            Box().frame(width: px(40), height: px(40)).onClick {}
        }
    }
    #expect(window.lastHitboxes.count == 2 && window.lastHitboxes.allSatisfy(\.opaque),
            "the two click targets and nothing else: \(window.lastHitboxes.map(\.opaque))")
    let before = window.hoverVisits
    platform.simulateInput(mv(100, 100))
    platform.simulateInput(mv(100, 60))
    psRedraw(window)
    #expect(window.hoverVisits == before, "no hover work without a hover region")
    withExtendedLifetime(window) {}
}

/// **2.56** (`SV-U`). One hover recompute visits each hitbox once (after the
/// one ranking): a branching tree of five hitboxes — an outer region, a hover
/// tile, a click tile, and a tile with both (two hitboxes) — costs 5 visits
/// per pointer event. Literal derived before the run: 1 + 1 + 1 + 2 = 5.
/// Mutation: a nested loop over ancestors × hitboxes.
@MainActor
@Test func hoverRecomputeVisitsEachHitboxOnce() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow {
        Column {
            Row {
                tile(m, "a", 30, 30)
                Box().frame(width: px(30), height: px(30)).onClick {}
            }
            Row {
                tile(m, "c", 30, 30).onClick {}
                Box().frame(width: px(30), height: px(30))
            }
        }
        .onHover { m.log.append("outer \($0)") }
    }
    try #require(window.lastHitboxes.count == 5, "set up: \(window.lastHitboxes.count) hitboxes")
    let before = window.hoverVisits
    platform.simulateInput(mv(100, 100))
    #expect(window.hoverVisits - before == 5)
    platform.simulateInput(mv(101, 101))
    #expect(window.hoverVisits - before == 10)
    withExtendedLifetime(window) {}
}

/// **2.57** (`SV-Z`). Of two overlapping sibling hover regions only the one
/// ranked above hovers over the overlap; the one beneath hovers where it is
/// uncovered. Mutation: eligibility `\.opaque` alone (the beneath one reads
/// `true` over the overlap).
@MainActor
@Test func anOverlappingSiblingHoverRegionCoversTheOneBeneath() throws {
    let m = HVModel()
    let (window, platform) = try hvWindow {
        ZStack {
            Rectangle(width: px(100), height: px(100)).onHover { m.log.append("beneath \($0)") }
            Rectangle(width: px(40), height: px(40)).onHover { m.log.append("top \($0)") }
        }
    }
    platform.simulateInput(mv(100, 100))
    #expect(m.log == ["top true"], "over the overlap only the top hovers: \(m.log)")
    platform.simulateInput(mv(60, 60))
    #expect(m.log == ["top true", "top false", "beneath true"])
    withExtendedLifetime(window) {}
}
