import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// `HSplitView` / `VSplitView` (rulings `HS-A`...`HS-H`, `docs/superpowers/2026-10-30-split-view-decisions.md`)
// through the public harness: plain imports, portable, no sleeping. The 400 x 300 window is filled by the split
// view (its proposal is finite), so two 1-point dividers leave 398 points for the panes. Panes are read from the
// presented rects: full-height rects wider than a divider, in x order (VSplitView: full-width, in y order).

/// In-memory autosave store (`HS-G`).
@MainActor private final class MemoryStore: SplitViewAutosaveStore {
    var saved: [String: [Double]] = [:]
    var writes = 0
    func paneSizes(forName name: String) -> [Double]? { saved[name] }
    func setPaneSizes(_ sizes: [Double], forName name: String) { saved[name] = sizes; writes += 1 }
}

/// The visible rects (the divider's transparent hit area paints a clear rect).
@MainActor private func painted(_ window: TestWindow) -> [MUIRect] {
    window.scene.rects.filter { $0.background.a > 0 }
}

@MainActor private func columns(_ window: TestWindow) -> [Float] {
    painted(window).filter { $0.bounds.size.height == 300 && $0.bounds.size.width > 1 }
        .sorted { $0.bounds.origin.x < $1.bounds.origin.x }.map { $0.bounds.size.width }
}

@MainActor private func rows(_ window: TestWindow) -> [Float] {
    painted(window).filter { $0.bounds.size.width == 400 && $0.bounds.size.height > 1 }
        .sorted { $0.bounds.origin.y < $1.bounds.origin.y }.map { $0.bounds.size.height }
}

@MainActor private func dividerXs(_ window: TestWindow) -> [Float] {
    painted(window).filter { $0.bounds.size.height == 300 && $0.bounds.size.width == 1 }
        .sorted { $0.bounds.origin.x < $1.bounds.origin.x }.map { $0.bounds.origin.x }
}

/// Palette | canvas | inspector: A ideal 100 (50...200), B no limits, C ideal 120 (60...240).
@MainActor private func threePanes(store: MemoryStore? = nil, name: String? = nil) -> some Element {
    let split = HSplitView {
        Color.red.frame(minWidth: 50, idealWidth: 100, maxWidth: 200)
        Color.green
        Color.blue.frame(minWidth: 60, idealWidth: 120, maxWidth: 240)
    }
    return VStack(spacing: 0) {
        if let name { split.splitViewAutosaveName(name, store: store) } else { split }
    }
}

/// HS-B — the panes start at their ideal widths and the pane without limits takes what is left:
/// 398 - 100 - 120 = 178. Mutation: `solve` starts from the minimum instead of the ideal.
@Test @MainActor func panesStartAtTheirIdealWidthsAndTheFlexiblePaneTakesTheRest() throws {
    let window = try harnessWindow { threePanes() }
    #expect(columns(window) == [100, 178, 120], "\(columns(window))")
    #expect(dividerXs(window) == [100, 279], "\(dividerXs(window))")
}

/// HS-D — dragging divider 0 right by 30 resizes its two neighbours and nothing else.
/// Mutation: `dragged` leaves the second pane of the pair alone.
@Test @MainActor func draggingADividerResizesItsTwoNeighbours() throws {
    let window = try harnessWindow { threePanes() }
    window.drag(from: pt(100.5, 150), to: pt(130.5, 150))
    #expect(columns(window) == [130, 148, 120], "\(columns(window))")
    window.drag(from: pt(279.5, 150), to: pt(249.5, 150))
    #expect(columns(window) == [130, 118, 150], "\(columns(window))")
}

/// HS-C — a drag stops at the pane maxima and minima: A tops out at 200, bottoms at 50, and the
/// neighbour that would pass its own limit stops it too. Mutation: `dragged` ignores `maximums`.
@Test @MainActor func aDragIsClampedToTheNeighboursLimits() throws {
    let window = try harnessWindow { threePanes() }
    window.drag(from: pt(100.5, 150), to: pt(300.5, 150))
    #expect(columns(window) == [200, 78, 120], "\(columns(window))")
    window.drag(from: pt(200.5, 150), to: pt(0.5, 150))
    #expect(columns(window) == [50, 228, 120], "\(columns(window))")
    // Divider 1 right: C shrinks to its minimum 60 and stops there.
    window.drag(from: pt(278.5, 150), to: pt(398.5, 150))
    #expect(columns(window) == [50, 288, 60], "\(columns(window))")
}

/// HS-D — the clamp is on the total translation from the press, not accumulated: the pointer goes far
/// past A's maximum and back to +30, and A follows it to 130. Mutation: `dragged` is applied to the
/// previous event's sizes instead of the snapshot taken at the press.
@Test @MainActor func goingPastALimitAndBackFollowsThePointer() throws {
    let window = try harnessWindow { threePanes() }
    func event(_ x: Float) -> MouseEvent { MouseEvent(position: pt(x, 150)) }
    window.send(.mouseMoved(event(100.5)))
    window.send(.mouseDown(event(100.5)))
    window.send(.mouseDragged(event(300.5)))
    window.tick()
    #expect(columns(window) == [200, 78, 120], "\(columns(window))")
    window.send(.mouseDragged(event(130.5)))
    window.tick()
    #expect(columns(window) == [130, 148, 120], "\(columns(window))")
    window.send(.mouseUp(event(130.5)))
    window.tick()
    #expect(columns(window) == [130, 148, 120], "\(columns(window))")
}

/// HS-C — when the window grows, the extra space goes to the pane with no maximum; when it shrinks, that
/// pane gives it up. A and C keep their widths. Mutation: `solve` spreads over the bounded panes first.
@Test @MainActor func windowResizeGivesTheSpaceToTheFlexiblePane() throws {
    let window = try harnessWindow { threePanes() }
    window.resize(to: sz(600, 300))
    #expect(painted(window).filter { $0.bounds.size.height == 300 && $0.bounds.size.width > 1 }
        .sorted { $0.bounds.origin.x < $1.bounds.origin.x }.map { $0.bounds.size.width } == [100, 378, 120])
    window.resize(to: sz(300, 300))
    #expect(painted(window).filter { $0.bounds.size.height == 300 && $0.bounds.size.width > 1 }
        .sorted { $0.bounds.origin.x < $1.bounds.origin.x }.map { $0.bounds.size.width } == [100, 78, 120])
}

/// HS-C — a size the user chose survives a window resize: only the flexible pane changes.
/// Mutation: the stored sizes are discarded when the available space differs from their sum.
@Test @MainActor func aDraggedSizeSurvivesAWindowResize() throws {
    let window = try harnessWindow { threePanes() }
    window.drag(from: pt(100.5, 150), to: pt(130.5, 150))
    window.resize(to: sz(500, 300))
    #expect(painted(window).filter { $0.bounds.size.height == 300 && $0.bounds.size.width > 1 }
        .sorted { $0.bounds.origin.x < $1.bounds.origin.x }.map { $0.bounds.size.width } == [130, 248, 120])
}

/// HS-F — the divider paints one 1-point rect and the resize pointer shows over its 6-point hit area
/// (x 97.5...103.5 around the line at 100...101) and not beyond it. Mutation: `columnResize` replaced by
/// `rowResize`; the hit area narrowed to the 1-point line.
@Test @MainActor func theDividerShowsTheColumnResizePointerOverItsHitArea() throws {
    let window = try harnessWindow { threePanes() }
    window.hover(at: pt(98, 150))
    #expect(window.pointerStyle == .columnResize)
    window.hover(at: pt(103, 150))
    #expect(window.pointerStyle == .columnResize)
    window.hover(at: pt(90, 150))
    #expect(window.pointerStyle == .arrow)
    window.hover(at: pt(110, 150))
    #expect(window.pointerStyle == .arrow)
}

/// HS-G — a drag saves the sizes once, at its end, and a new window built with the same name and store
/// starts from them. Mutation: `dragEnded` does not save; `requestLayout` ignores the store.
@Test @MainActor func autosaveRoundTripsThroughTheInjectedStore() throws {
    let store = MemoryStore()
    let window = try harnessWindow { threePanes(store: store, name: "main") }
    #expect(store.saved["main"] == nil)
    window.drag(from: pt(100.5, 150), to: pt(130.5, 150))
    #expect(store.saved["main"] == [130, 148, 120], "\(String(describing: store.saved))")
    #expect(store.writes == 1)
    let reopened = try harnessWindow { threePanes(store: store, name: "main") }
    #expect(columns(reopened) == [130, 148, 120], "\(columns(reopened))")
    let other = try harnessWindow { threePanes(store: store, name: "other") }
    #expect(columns(other) == [100, 178, 120], "a different name does not restore")
}

/// HS-D — a press on the divider that does not move writes no sizes (and nothing to the store).
/// Mutation: `dragChanged` writes sizes for a zero translation.
@Test @MainActor func aClickOnTheDividerChangesNothing() throws {
    let store = MemoryStore()
    let window = try harnessWindow { threePanes(store: store, name: "main") }
    window.click(at: pt(100.5, 150))
    #expect(columns(window) == [100, 178, 120])
    #expect(store.writes == 0)
}

/// HS-H — `VSplitView` is the same algorithm on the vertical axis: heights start at the ideals, a drag
/// resizes the neighbours with the clamps, the hit area shows the row-resize pointer.
/// Mutation: `SplitLayout` reads `width` for the vertical axis.
@Test @MainActor func aVSplitViewIsTheSameOnTheVerticalAxis() throws {
    let window = try harnessWindow {
        VSplitView {
            Color.red.frame(minHeight: 40, idealHeight: 60, maxHeight: 100)
            Color.green
            Color.blue.frame(minHeight: 30, idealHeight: 90, maxHeight: 200)
        }
    }
    #expect(rows(window) == [60, 148, 90], "\(rows(window))")
    window.drag(from: pt(200, 60.5), to: pt(200, 80.5))
    #expect(rows(window) == [80, 128, 90], "\(rows(window))")
    window.drag(from: pt(200, 80.5), to: pt(200, 250))
    #expect(rows(window) == [100, 108, 90], "\(rows(window))")
    window.hover(at: pt(200, 101))
    #expect(window.pointerStyle == .rowResize)
    window.hover(at: pt(200, 50))
    #expect(window.pointerStyle == .arrow)
    window.resize(to: sz(400, 400))
    #expect(rows(window) == [100, 208, 90], "\(rows(window))")
}

/// HS-C — with no pane unbounded the surplus is shared by the bounded ones, equally while each has
/// room: A (ideal 100, max 150) and B (ideal 100, max 300) in 399 points: 199 spare, A takes 50 to its
/// maximum, B the other 149. Mutation: the bounded pass is skipped, leaving the surplus unplaced.
@Test @MainActor func withNoUnboundedPaneTheBoundedOnesShareTheSurplus() throws {
    let window = try harnessWindow {
        HSplitView {
            Color.red.frame(minWidth: 50, idealWidth: 100, maxWidth: 150)
            Color.blue.frame(minWidth: 50, idealWidth: 100, maxWidth: 300)
        }
    }
    #expect(columns(window) == [150, 249], "\(columns(window))")
}

/// HS-D — a drag stops when the pane on the far side would pass its own maximum, and the pane beyond
/// that one does not move: B (max 150) cannot take A's 100 points, so A stops at 100 and C stays 148
/// (the solver's re-clamp alone would hand the excess to C). Mutation: `dragged` drops
/// `total - maximums[b]` from the lower bound.
@Test @MainActor func aDragStopsWhereTheFarNeighbourReachesItsMaximum() throws {
    let window = try harnessWindow {
        HSplitView {
            Color.red.frame(minWidth: 50, idealWidth: 150, maxWidth: 400)
            Color.green.frame(minWidth: 50, idealWidth: 100, maxWidth: 150)
            Color.blue
        }
    }
    #expect(columns(window) == [150, 100, 148], "\(columns(window))")
    window.drag(from: pt(150.5, 150), to: pt(20.5, 150))
    #expect(columns(window) == [100, 150, 148], "\(columns(window))")
}
