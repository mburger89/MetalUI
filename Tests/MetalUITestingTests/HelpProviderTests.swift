@testable import MetalUI
import MetalUITesting
import Testing

// `MN-AJ` (record 239): `.help { location in String? }`, a model-driven tooltip. Portable: the real `Window` over
// `MetalUITesting`, nothing sleeps (the clock is `TestWindow`'s). Geometry: a 400 × 300 window, a 200 × 100 surface
// centred at (200, 150), so local = window − (100, 100). The provider answers "A" for local x < 50, "B" for
// 50 ..< 100 and nothing beyond.

/// Every call the provider has had, with the local point it was handed.
@MainActor private final class ProviderLog {
    var points: [Point<Pixels>] = []
    var count: Int { points.count }
}

@MainActor private func answer(_ location: Point<Pixels>) -> String? {
    location.x.value < 50 ? "A" : (location.x.value < 100 ? "B" : nil)
}

/// The surface under test, legacy vocabulary.
@MainActor private func providerWindow(_ log: ProviderLog = ProviderLog()) throws -> TestWindow {
    try harnessWindow {
        Box().frame(width: Pixels(200), height: Pixels(100)).background(.accent).help { location in
            log.points.append(location)
            return answer(location)
        }
    }
}

private let inA = pt(110, 150), inA2 = pt(130, 120), inB = pt(180, 150), inNothing = pt(250, 150)

@MainActor private func shown(_ window: TestWindow) -> String? { window.window.visibleTooltip?.text }

/// The provider's text appears after the delay at an "A" point, not before.
/// Mutation: `trackTooltip` ignoring `helpProvider` in the `wanted` predicate (red: nothing is found).
@Test @MainActor func aProviderTooltipAppearsAfterTheDelay() throws {
    let window = try providerWindow()
    window.hover(at: inA)
    window.advance(by: 0.5)
    #expect(shown(window) == nil, "the delay has not passed")
    window.advance(by: 0.6)
    #expect(shown(window) == "A")
}

/// The point is handed in the element's local space.
/// Mutation: `Point(x: inRegion.x, ...)` without subtracting `region.origin` (red: x 110 reads "B"... nothing local).
@Test @MainActor func theProviderIsHandedTheLocalPoint() throws {
    let log = ProviderLog()
    let window = try providerWindow(log)
    window.hover(at: inA)
    let last = try #require(log.points.last)
    #expect(last == Point(x: Pixels(10), y: Pixels(50)))
}

/// Moving to a point with another text hides the bubble and restarts the delay for the new text.
/// Mutation: the text comparison removed (`text == providedText` always true: "B" never shows).
@Test @MainActor func movingToAnotherTextHidesAndRestartsTheDelay() throws {
    let window = try providerWindow()
    window.hover(at: inA)
    window.advance(by: 1.1)
    try #require(shown(window) == "A")
    window.hover(at: inB)
    #expect(shown(window) == nil, "the bubble is hidden at once")
    window.advance(by: 0.5)
    #expect(shown(window) == nil, "the delay restarted")
    window.advance(by: 0.6)
    #expect(shown(window) == "B")
}

/// Moving within the same text keeps a shown bubble, and does not restart a pending one.
/// Mutation: `providedText` stored as nil on a same-text move (red: both arms).
@Test @MainActor func movingWithinTheSameTextKeepsItAndDoesNotRestart() throws {
    let window = try providerWindow()
    window.hover(at: inA)
    window.advance(by: 0.6)
    window.hover(at: inA2)
    window.advance(by: 0.6)
    #expect(shown(window) == "A", "the timer ran on from the first move: 1.2 s, not 0.6 s")
    window.hover(at: pt(120, 140))
    #expect(shown(window) == "A", "a shown bubble stays")
}

/// A point with no text shows nothing, and leaving a text for it hides the bubble.
/// Mutation: a nil answer leaving the phase as it was (red: "A" stays after the move).
@Test @MainActor func aNilAnswerShowsNothingAndHidesTheBubble() throws {
    let window = try providerWindow()
    window.hover(at: inNothing)
    window.advance(by: 2)
    #expect(shown(window) == nil)
    window.hover(at: inA)
    window.advance(by: 1.1)
    try #require(shown(window) == "A")
    window.hover(at: inNothing)
    #expect(shown(window) == nil)
    window.advance(by: 2)
    #expect(shown(window) == nil)
    window.hover(at: inB)
    window.advance(by: 1.1)
    #expect(shown(window) == "B", "back onto a text, the tooltip comes back")
}

/// A press, a wheel event, a key and leaving the surface each hide it; after a press the same text stays hidden and
/// another text restarts.
/// Mutation: the `.mouseDown` arm removed from `trackTooltip` (red: press arm); `providedText` not reset on a hide is
/// pinned by the last two expectations.
@Test @MainActor func pressWheelKeyAndLeavingHideIt() throws {
    let window = try providerWindow()
    func showA() throws {
        window.hover(at: inA)
        window.advance(by: 1.1)
        try #require(shown(window) == "A")
    }
    try showA()
    window.click(at: inA)
    #expect(shown(window) == nil, "a press hides")
    window.hover(at: inA2)
    window.advance(by: 2)
    #expect(shown(window) == nil, "the same text stays spent")
    window.hover(at: inB)
    window.advance(by: 1.1)
    #expect(shown(window) == "B", "another text returns after the delay")

    window.hover(at: inA)
    window.advance(by: 1.1)
    try #require(shown(window) == "A")
    window.scroll(at: inA, byDeltaX: 0, deltaY: 5)
    #expect(shown(window) == nil, "a wheel event hides")

    window.hover(at: inNothing)
    window.hover(at: inA)
    window.advance(by: 1.1)
    try #require(shown(window) == "A")
    window.typeKey("a")
    #expect(shown(window) == nil, "a key hides")

    window.hover(at: inNothing)
    window.hover(at: inA)
    window.advance(by: 1.1)
    try #require(shown(window) == "A")
    window.hover(at: pt(20, 20))
    #expect(shown(window) == nil, "leaving hides")
    window.advance(by: 2)
    #expect(shown(window) == nil)
}

/// The provider runs in input only: once per pointer move, never while frames are laid out, prepainted and painted.
/// Mutation: calling `provider` from `registerHandlers`-side code (here: a call added to `advanceTooltip`) reddens
/// the frame arm.
@Test @MainActor func theProviderRunsInInputNeverInAPhase() throws {
    let log = ProviderLog()
    let window = try providerWindow(log)
    #expect(log.count == 0, "mounting and the first frames ask nothing")
    window.hover(at: inA)
    #expect(log.count == 1, "one move, one call")
    window.advanceFrames(10)
    window.advance(by: 1.5)
    window.window.setNeedsRedraw()
    window.advanceFrames(3)
    #expect(log.count == 1, "ticks, redraws and the tooltip's own show ask nothing")
    window.hover(at: inB)
    #expect(log.count == 2)
}

/// `.allowsHitTesting(false)` still shows no `.help` of a child (`MN-U`), while the surface under it answers.
/// Mutation: `hitTestingDisabledDepth == 0` gate dropped around the contextual region in `Frame` (red: "Child" wins).
@Test @MainActor func aNonHitTestingChildShowsNothingWhileTheSurfaceAnswers() throws {
    let window = try harnessWindow {
        ZStack {
            Rectangle().fill(Color.blue).frame(width: 200, height: 100).help { _ in "Surface" }
            Rectangle().fill(Color.red).frame(width: 100, height: 100).help("Child").allowsHitTesting(false)
        }
    }
    window.hover(at: pt(200, 150))
    window.advance(by: 1.1)
    #expect(shown(window) == "Surface", "the child's own help is skipped (MN-U), the surface's provider shows")

    let alone = try harnessWindow {
        Rectangle().fill(Color.red).frame(width: 100, height: 100).help("Child").allowsHitTesting(false)
    }
    alone.hover(at: pt(200, 150))
    alone.advance(by: 1.1)
    #expect(shown(alone) == nil, "MN-U unchanged")
}

/// The proposal-path spelling works the same.
/// Mutation: the `ProposalElementGroup` overload's attachment built with `help: ""` and no provider (red).
@Test @MainActor func theProposalPathSpellingShowsToo() throws {
    let window = try harnessWindow {
        Rectangle().fill(Color.blue).frame(width: 200, height: 100).help { location in answer(location) }
    }
    window.hover(at: inB)
    window.advance(by: 1.1)
    #expect(shown(window) == "B")
}

/// MN-AM 2 — a provider answering `""` shows no tooltip, as `nil` does.
/// Mutation: drop the `isEmpty` line after the provider call (the bubble shows "").
@Test @MainActor func aProviderAnsweringEmptyShowsNoTooltip() throws {
    let window = try harnessWindow {
        Box().frame(width: Pixels(200), height: Pixels(100)).background(.accent).help { _ in "" }
    }
    window.hover(at: inA)
    window.advance(by: 2)
    #expect(shown(window) == nil)
}
