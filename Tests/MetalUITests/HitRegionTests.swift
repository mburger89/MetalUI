import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
@testable import MetalUI

// Lane 3 of plan task 5
// (`docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`): **hit
// testing** — `allowsHitTesting(_:)` and `contentShape(inset:)`, the two
// prepaint-only modifiers of the task's eleven.
//
// Rulings: `OM-I`, `OM-J`, `OM-K`, `OM-T`, `OM-X`, `OM-AB` and `OM-AJ` in
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
