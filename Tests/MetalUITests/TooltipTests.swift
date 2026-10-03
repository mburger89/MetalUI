import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Menus, popovers and tooltips, lane 3, tests 3.17–3.25 (rulings `MN-P`,
// `MN-U`, `MN-V` item 3; spec
// `docs/superpowers/specs/2026-10-02-menus-popovers-design.md` §3.10, §6.3).
// SwiftUI's `.help` accessibility is the probe's H1–H5; the tooltip itself is
// MetalUI's own (H6/H7 measured no tooltip headless, divergence 113).
//
// A real `Window` on a 400 × 400 `FakePlatformWindow` whose display link the
// test drives with `simulateTick(timestamp:)` — nothing sleeps.

// MARK: - Fixtures

@MainActor
private final class TLog { var entries: [String] = [] }

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func ldown(_ x: Float, _ y: Float) -> InputEvent { .mouseDown(MouseEvent(position: pt(x, y))) }
private func lup(_ x: Float, _ y: Float) -> InputEvent { .mouseUp(MouseEvent(position: pt(x, y))) }
private func moved(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }
private func key(_ c: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: [], timestamp: 0))
}

/// A 400 × 200 box explaining itself above a plain 400 × 200 box.
@MainActor private func helpRoot() -> some Element {
    Column {
        Box().frame(width: px(400), height: px(200)).help("Explains")
        Box().frame(width: px(400), height: px(200))
    }
}

/// A 400 × 400 window over `content` whose display link the test ticks.
@MainActor
private func tooltipWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true, content: content)
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// Shows the tooltip over (100, 100): enter, stamp at 10, show at 11.
@MainActor private func show(_ window: Window, _ platform: FakePlatformWindow,
                             sourceLocation: SourceLocation = #_sourceLocation) throws {
    platform.simulateInput(moved(100, 100))
    platform.simulateTick(timestamp: 10)
    platform.simulateTick(timestamp: 11)
    try #require(window.visibleTooltip?.text == "Explains", "the tooltip is shown", sourceLocation: sourceLocation)
}

// MARK: - 3.17–3.20: timing and hiding

/// **3.17** (divergence 113, `MN-P` item 2). The tooltip appears after 1.0 s of
/// display-link time: stamped at the first tick (10.0), not at 10.9, at 11.0.
/// Mutation: delay 0.
@MainActor
@Test func aTooltipAppearsAfterTheHoverDelayOfTickTime() throws {
    let (window, platform) = try tooltipWindow { helpRoot() }
    platform.simulateInput(moved(100, 100))
    platform.simulateTick(timestamp: 10.0)
    #expect(window.visibleTooltip == nil, "10.0: stamped, not shown")
    platform.simulateTick(timestamp: 10.9)
    #expect(window.visibleTooltip == nil, "10.9: not yet")
    platform.simulateTick(timestamp: 11.0)
    #expect(window.visibleTooltip?.text == "Explains", "11.0: shown")
    withExtendedLifetime(window) {}
}

/// **3.18** (`MN-P` item 2, `IX-C`'s "a stamp is always a real tick"). The
/// delay is stamped from the first tick after the pointer entered, never from
/// the window's stale last tick (0 here, no tick yet): 50.0 stamps, 50.5 is
/// not enough, 51.0 shows. Mutation: stamp from the stale `lastTick`.
@MainActor
@Test func theTooltipDelayIsStampedFromTheFirstTickAfterEntering() throws {
    let (window, platform) = try tooltipWindow { helpRoot() }
    platform.simulateInput(moved(100, 100))
    platform.simulateTick(timestamp: 50.0)
    #expect(window.visibleTooltip == nil, "50.0 stamps")
    platform.simulateTick(timestamp: 50.5)
    #expect(window.visibleTooltip == nil, "50.5: half the delay")
    platform.simulateTick(timestamp: 51.0)
    #expect(window.visibleTooltip != nil, "51.0: shown")
    withExtendedLifetime(window) {}
}

/// **3.19** (`MN-P` item 2). A press, a wheel event, a key-down and leaving the
/// region each hide the tooltip. Mutation: drop the press rule.
@MainActor
@Test(arguments: ["press", "wheel", "key", "leave"])
func aPressAWheelAKeyOrLeavingHidesTheTooltip(_ cause: String) throws {
    let (window, platform) = try tooltipWindow { helpRoot() }
    try show(window, platform)
    switch cause {
    case "press":
        platform.simulateInput(ldown(100, 100))
        platform.simulateInput(lup(100, 100))
    case "wheel":
        platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(100, 100), delta: pt(0, 5))))
    case "key":
        platform.simulateInput(key("a"))
    default:
        platform.simulateInput(moved(100, 300))
    }
    #expect(window.visibleTooltip == nil, "hidden by \(cause)")
    withExtendedLifetime(window) {}
}

/// **3.20** (`MN-P` item 2). After a hide the tooltip does not return while
/// the pointer stays in the region, whatever it does there; leaving,
/// re-entering and the delay bring it back. Mutation: clear the spent mark on
/// any move.
@MainActor
@Test func aHiddenTooltipReturnsOnlyAfterLeavingAndReentering() throws {
    let (window, platform) = try tooltipWindow { helpRoot() }
    try show(window, platform)
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(lup(100, 100))
    platform.simulateInput(moved(110, 110))
    platform.simulateInput(moved(120, 120))
    platform.simulateTick(timestamp: 12)
    platform.simulateTick(timestamp: 13.5)
    #expect(window.visibleTooltip == nil, "moves inside after a press: never")
    platform.simulateInput(moved(100, 300))
    platform.simulateInput(moved(100, 100))
    platform.simulateTick(timestamp: 14)
    platform.simulateTick(timestamp: 15)
    #expect(window.visibleTooltip?.text == "Explains", "left, re-entered and waited: shown")
    withExtendedLifetime(window) {}
}

// MARK: - 3.21: placement

/// **3.21** (`MN-P` item 2). The tooltip's top-left corner sits 18 pt below the
/// pointer; near the bottom it flips above (its bottom 4 pt above the
/// pointer); it is clamped inside the window with 4 pt. Mutation: no flip.
@MainActor
@Test func theTooltipIsPlacedBelowThePointerAndFlippedInsideTheWindow() {
    let window = Size(width: px(400), height: px(400))
    let size = Size(width: px(100), height: px(20))
    func origin(_ x: Float, _ y: Float) -> [Float] {
        let p = TooltipPlacement.origin(pointer: pt(x, y), size: size, window: window)
        return [p.x.value, p.y.value]
    }
    #expect(origin(50, 50) == [50, 68], "18 pt below")
    #expect(origin(50, 390) == [50, 366], "near the bottom, above: 390 − 4 − 20")
    #expect(origin(380, 50) == [296, 68], "clamped 4 pt from the right")
    #expect(origin(0, 50) == [4, 68], "clamped 4 pt from the left")
}

// MARK: - 3.22–3.23: accessibility and hit testing

/// **3.22** (H1–H5, `MN-P` item 1). `.help` publishes exactly the tree
/// `.accessibilityHint` does, for each shape the probe measured: one element
/// (H1), a `Button` with the other spelling inside and outside (H3, H3b), a
/// distributing container (H4), an outer one over an inner one (H5) — and on
/// the proposal path. Mutation: write the help as the label.
@MainActor
@Test func helpPublishesTheSameTreeAsAccessibilityHint() throws {
    func tree<E: Element>(_ root: E) throws -> AccessibilityTree { try accessibilityBuild(root).1.tree }
    let shapes: [(String, () throws -> (AccessibilityTree, AccessibilityTree))] = [
        ("H1", { (try tree(Text("T").help("h")), try tree(Text("T").accessibilityHint("h"))) }),
        ("H3", { (try tree(Button("B") {}.accessibilityHint("in").help("out")),
                  try tree(Button("B") {}.accessibilityHint("in").accessibilityHint("out"))) }),
        ("H3b", { (try tree(Button("B") {}.help("in").accessibilityHint("out")),
                   try tree(Button("B") {}.accessibilityHint("in").accessibilityHint("out"))) }),
        ("H4", { (try tree(Column { Text("a"); Text("b") }.help("h")),
                  try tree(Column { Text("a"); Text("b") }.accessibilityHint("h"))) }),
        ("H5", { (try tree(Column { Text("a").help("in") }.help("out")),
                  try tree(Column { Text("a").accessibilityHint("in") }.accessibilityHint("out"))) }),
        ("proposal", { (try tree(HStack { ProposalText("a"); ProposalText("b") }.help("h")),
                        try tree(HStack { ProposalText("a"); ProposalText("b") }.accessibilityHint("h"))) }),
    ]
    for (name, make) in shapes {
        let (help, hint) = try make()
        try #require(!hint.nodes.isEmpty, "\(name): the control publishes something")
        #expect(help == hint, "\(name): .help publishes .accessibilityHint's tree")
        #expect(help.nodes.values.contains { $0.hint != nil }, "\(name): a hint is published")
    }
}

/// **3.23** (`MN-V`, `DN-E`'s shape). A help region is no pointer target: a
/// click on a `Button` under a box explaining itself still presses the
/// button, and a `Handlers` carrying only the attachment is not a pointer
/// target. Mutation: make the region opaque.
@MainActor
@Test func aHelpRegionAddsNoPointerTarget() throws {
    let log = TLog()
    let (window, platform) = try tooltipWindow {
        Button("Under") { log.entries.append("under") }.frame(width: px(400), height: px(400))
            .overlay { Box().frame(width: px(400), height: px(400)).help("h") }
    }
    try #require(window.lastHitboxes.contains { !$0.opaque && $0.handlers.contextual?.help == "h" },
                 "the help region is registered")
    platform.simulateInput(ldown(200, 200))
    platform.simulateInput(lup(200, 200))
    #expect(log.entries == ["under"], "the click reached the button beneath")
    var handlers = Handlers()
    handlers.contextual = ContextualAttachment(menu: nil, help: "h")
    #expect(!handlers.isPointerTarget)
    withExtendedLifetime(window) {}
}

// MARK: - 3.24–3.25: the display link and paint order

/// **3.24** (`MN-P` item 2, `IX-C` item 4's footing). A pending tooltip keeps
/// frames coming — one per tick, the showing tick included — and once it is
/// shown the idle window pauses again. Mutation: leave the link paused.
@MainActor
@Test func thePendingTooltipKeepsTheLinkAwakeOnlyWhilePending() throws {
    let (window, platform) = try tooltipWindow { helpRoot() }
    platform.simulateTick(timestamp: 1)
    let idle = window.framesDrawn
    platform.simulateTick(timestamp: 2)
    try #require(window.framesDrawn == idle, "control: an idle window draws nothing")
    platform.simulateInput(moved(100, 100))
    var drawn: [Int] = []
    for t in [10.0, 10.5, 11.0, 11.5, 12.0] {
        let before = window.framesDrawn
        platform.simulateTick(timestamp: t)
        drawn.append(window.framesDrawn - before)
    }
    #expect(window.visibleTooltip != nil)
    #expect(drawn == [1, 1, 1, 0, 0], "a frame per tick while pending, the showing one included; none after")
    #expect(platform.pauseCalls.last == true, "paused once shown and idle")
    withExtendedLifetime(window) {}
}

/// **3.25** (`MN-P` item 2). The tooltip paints above everything — above an
/// open in-window menu: its panel is the highest-layer primitive. Mutation:
/// emit before the menu panel.
@MainActor
@Test func theTooltipIsPaintedAboveEverything() throws {
    let log = TLog()
    let (window, platform) = try tooltipWindow { helpRoot() }
    platform.presentsMenusNatively = false
    try show(window, platform)
    let attachment = ContextualAttachment(menu: { MenuItems([Button("Copy") { log.entries.append("copy") }]) },
                                          help: nil)
    try #require(window.openContextMenu(attachment, isEnabled: true,
                                        declaringID: GlobalElementID(component: .positional(0), parent: nil),
                                        at: pt(150, 150), openingPress: false), "a menu fixture is open")
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let tooltip = try #require(window.visibleTooltip, "still shown").frame
    let scene = window.lastScene
    let index = try #require(scene.rects.firstIndex {
        Float($0.bounds.origin.x) == tooltip.origin.x.value && Float($0.bounds.origin.y) == tooltip.origin.y.value
            && Float($0.bounds.size.width) == tooltip.size.width.value
    }, "the tooltip's panel is in the scene")
    let menu = try #require(window.menuSession?.levels.first?.frame)
    let menuIndex = try #require(scene.rects.firstIndex {
        Float($0.bounds.origin.x) == menu.origin.x.value && Float($0.bounds.origin.y) == menu.origin.y.value
    }, "the menu's panel is in the scene")
    #expect(scene.layer(of: .rect, at: index) > scene.layer(of: .rect, at: menuIndex), "above the menu")
    #expect(scene.layer(of: .rect, at: index) == scene.highestLayer, "the highest layer")
    withExtendedLifetime(window) {}
}
