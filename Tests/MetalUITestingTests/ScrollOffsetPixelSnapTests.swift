import Foundation
@testable import MetalUI
import MetalUICore
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
import Testing

// Record 426 (`DSA-J`): a scroller presents its offset on the device-pixel grid, `round(offset * scale) / scale`, as SwiftUI does (probe
// `docs/probes/swiftui-scroll-offset-pixel-snap.swift`): painted, laid out against, and stored are one number. Input accumulates its raw
// sub-pixel remainder separately (`ScrollState.residue`), so a slow scroll still advances.

private let psVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the refusal counts are not its to read"

/// A 300 x 300 scroller over rows of 40 pt, the fourth (index 3) 41 pt tall in a colour of its own: its painted device y is the probe.
private struct PSRoot: Component {
    var anchorBottom = false
    var content: some ElementGroup {
        if anchorBottom {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Color(red: 0.2, green: 0.9, blue: 0.1).frame(height: Pixels(399.5))
                }
            }.defaultScrollAnchor(.bottom).frame(width: Pixels(300), height: Pixels(300))
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(0..<20), id: \.self) { i in
                        Color(red: i == 3 ? 0.2 : 0.5, green: i == 3 ? 0.9 : 0.5, blue: i == 3 ? 0.1 : 0.5)
                            .frame(height: Pixels(i == 3 ? 41 : 40))
                    }
                }
            }.frame(width: Pixels(300), height: Pixels(300))
        }
    }
}

@MainActor private func psWindow(scale: Float, anchorBottom: Bool = false) throws -> TestWindow {
    let options = HeadlessPlatformWindow.Options(scaleFactor: scale, accessibilityClientActive: false)
    let w = try TestWindow(size: sz(320, 400), scaleFactor: scale, options: options, textSystem: { harnessTextSystem() }) {
        VStack(spacing: 0) { PSRoot(anchorBottom: anchorBottom) }
    }
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    return w
}

/// The scroller's stored state: what is committed, what input has left over.
@MainActor private func psState(_ w: TestWindow) throws -> ScrollState {
    let region = try #require(w.window.lastScrollRegions.first, "the scroller registered a region")
    return try #require(w.window.stateTable.peek(region.id, as: ScrollState.self))
}

/// The painted device y of the 41 pt marker row (the only rect that tall), in device pixels.
@MainActor private func psMarkerY(_ w: TestWindow, scale: Float) throws -> Float {
    let rect = try #require(w.scene.rects.first { $0.bounds.size.height == 41 * scale }, "the marker row is painted")
    return rect.bounds.origin.y
}

/// Wheel steps of 0.3 pt move a scroller of replayed rows by fractions of a device pixel: unsnapped, every moved record refused
/// (`fractionalTranslation`, then `inexactTranslation`) and the frame paid a redo. Snapped, a step moves by whole device pixels or not at
/// all, nothing is refused as fractional, rows replay translated, and the replayed frame equals a fresh one (`compare`) at every step.
/// Mutation: `presentedOffset` returning its unsnapped input (red at both scales: refusals, and at 2x a differing frame).
@Test(.enabled(if: !rsVerifying, psVerifyingNote), arguments: [Float(1), Float(2)]) @MainActor
func aFractionallyMovedRowReplaysExactly(scale: Float) async throws {
    let pair = try RPPair(size: sz(320, 400), scale: scale, warm: 4, accessibility: false, graft: true) { side in
        VStack(spacing: 0) { FSShiftSideRoot(side: side, kind: .scroll) }
    }
    var reasons: [String: Int] = [:]
    var translated = 0
    pair.on.resetFrameWork()
    for d: Float in [0.3, 0.3, 0.3, 0.5, 0.4, 0.3, 0.6, 0.3] {
        pair.on.resetFrameWork()
        for w in [pair.on, pair.off] { w.scroll(at: pt(160, 200), byDeltaX: 0, deltaY: -d) }
        await rsSettle(); pair.redraw()
        reasons.merge(pair.stepWork.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        translated += pair.stepWork.retainedTranslated
        try pair.compare("a wheel step of \(d) at scale \(scale)")
    }
    #expect(reasons["fractionalTranslation", default: 0] == 0 && reasons["inexactTranslation", default: 0] == 0, "refused: \(reasons)")
    #expect(translated > 0, "rows moved and replayed translated, or the test reads nothing")
}

/// Repeated 0.3 pt deltas still advance: ten of them are 3 pt at 1x and at 2x, presented a grid step at a time (1x: 0 1 1 1 2 2 2 2 3 3;
/// the raw position is 0.3, 0.6, ... and ties go up). Mutation: the residue dropped (`ScrollState.residue` always reset to 0), which
/// snaps the accumulator itself and stalls at 0 forever.
@Test(arguments: [Float(1), Float(2)]) @MainActor
func slowSubPixelScrollingStillAdvances(scale: Float) throws {
    let w = try psWindow(scale: scale)
    var seen: [Double] = []
    for _ in 0..<10 {
        w.scroll(at: pt(160, 100), byDeltaX: 0, deltaY: -0.3)
        w.window.setNeedsRedraw(); w.tick()
        seen.append(try psState(w).offset)
    }
    let last = try #require(seen.last)
    #expect(abs(last - 3) < 0.001, "ten 0.3 deltas move 3 pt: \(seen)")
    if scale == 1 { #expect(seen == [0, 1, 1, 1, 2, 2, 2, 2, 3, 3], "\(seen)") }
    #expect(seen == seen.sorted() && seen.allSatisfy { ($0 * Double(scale)).rounded() == $0 * Double(scale) }, "on the grid, never backwards: \(seen)")
}

/// A position a program chose is presented snapped: 100.3 is 100 at 1x and 100.5 at 2x (nearest half point), 100.7 is 101 and 100.5, a tie
/// goes up (100.5 is 101 at 1x). The committed offset (what `scrollPosition`, `ScrollContext` and the next layout read) equals the painted
/// one: the marker row's painted y is `(50 + 120 - offset) * scale` (the scroller sits at y = 50). Mutation: the commit in `resolveSlot` storing `clamped` instead.
@Test(arguments: [(Float(1), 100.3, 100.0), (Float(1), 100.7, 101.0), (Float(1), 100.5, 101.0),
                  (Float(2), 100.3, 100.5), (Float(2), 100.7, 100.5), (Float(2), 100.2, 100.0)])
@MainActor
func aProgrammaticFractionalPositionIsReportedSnapped(scale: Float, position: Double, expected: Double) throws {
    let w = try psWindow(scale: scale)
    let region = try #require(w.window.lastScrollRegions.first)
    w.window.stateTable.withState(region.id, initial: ScrollState()) { $0.offset = position }
    w.window.setNeedsRedraw(); w.tick()
    let state = try psState(w)
    #expect(state.offset == expected, "stored/reported \(state.offset)")
    let painted = try psMarkerY(w, scale: scale)
    #expect(painted == Float((50 + 120 - expected) * Double(scale)), "painted \(painted) rects \(w.scene.rects.map { [$0.bounds.origin.y, $0.bounds.size.height] })")
    w.window.setNeedsRedraw(); w.tick()
    let again = try psState(w).offset
    #expect(again == expected, "a second frame keeps it")
}

/// Probe F1 (content 399.5 in 300 under a bottom anchor): SwiftUI reports offset 99.0. The end of the content is the grid position at or
/// before it, never one past it (which would show a gap): 99 at 1x, and at 2x the half point 99.5 is on the grid and is the end (the probe
/// measured 99.0 under an injected 2x with a 1x window; the real 2x grid is a human check, `DSA-J`). Driven through `resolveSlot`, the
/// prepaint's commit: layout rounds rects to whole points (divergence 77), so a window never builds a fractional extent, and the window arm
/// below shows the whole-point extent sitting flush. Mutation: the end rounded to nearest instead of down (100 at 1x, past the content).
@Test(arguments: [(Float(1), 99.0), (Float(2), 99.5)]) @MainActor
func aBottomAnchoredScrollerWithAFractionalExtentSitsWhereSwiftUIPutsIt(scale: Float, expected: Double) throws {
    var chrome = ScrollChrome(axis: .vertical, cornerRadius: Pixels(0), indicatorVisibility: .automatic)
    chrome.anchors.declare(UnitPoint.bottom, for: nil)
    var offset = 0.0, residue = 0.3, glide: ScrollGlide?, memory = ScrollAnchorMemory(), extent = 0.0
    for _ in 0..<3 {   // the initial placement, then the pin holding it
        _ = chrome.resolveSlot(offset: &offset, residue: &residue, glide: &glide, anchor: &memory, viewportExtent: &extent,
                               content: 399.5, viewport: 300, scale: scale, now: 0)
        #expect(offset == expected, "the anchored offset \(offset)")
    }
    #expect(residue == 0, "a placement owes input nothing")
    #expect(399.5 - offset - 300 < 1 / Double(scale), "no more than a grid step of the content hangs past the viewport")
}

/// The same scroller in a window: a whole-point extent is flush with the end at both scales (offset 100 of 400 in 300).
@Test(arguments: [Float(1), Float(2)]) @MainActor
func aBottomAnchoredScrollerInAWindowSitsFlushWithTheEnd(scale: Float) throws {
    let w = try psWindow(scale: scale, anchorBottom: true)
    for _ in 0..<2 { w.window.setNeedsRedraw(); w.tick() }
    let state = try psState(w)
    #expect(state.offset == 100 && state.residue == 0, "the anchored offset \(state.offset)")
}

/// The presented offset is a pure function: idempotent (paint re-applies it to what prepaint committed), on the grid, inside `0...end`.
/// Mutation: the end bound using `snap` (nearest) instead of `snapDown`.
@Test @MainActor
func thePresentedOffsetIsIdempotentAndNeverPastTheEnd() {
    let chrome = ScrollChrome(axis: .vertical, cornerRadius: Pixels(0), indicatorVisibility: .automatic)
    for scale: Float in [1, 1.2, 1.5, 2, 3] {
        for raw in stride(from: -3.0, through: 130.0, by: 0.173) {
            let once = chrome.presentedOffset(raw, content: 399.5, viewport: 300, scale: scale)
            #expect(chrome.presentedOffset(once, content: 399.5, viewport: 300, scale: scale) == once, "scale \(scale) raw \(raw)")
            #expect(once >= 0 && once <= 99.5, "scale \(scale) raw \(raw): \(once)")
        }
    }
    #expect(chrome.presentedOffset(99.5, content: 399.5, viewport: 300, scale: 1) == 99)
    #expect(chrome.presentedOffset(99.5, content: 399.5, viewport: 300, scale: 2) == 99.5)
    #expect(ScrollChrome.snap(30.25, scale: 1) == 30 && ScrollChrome.snap(30.25, scale: 2) == 30.5 && ScrollChrome.snap(30.5, scale: 1) == 31)
}

/// Snapping costs nothing a frame feels: an idle frame of a scroller left with a sub-pixel residue makes exactly the allocations of one
/// with none, requests no element, and writes no state (the compared write finds the same value).
/// Mutation: an allocation in `snap` (an array literal) reddens the pinned count.
@Test(.enabled(if: !rsVerifying, psVerifyingNote)) @MainActor
func snappingAddsNoAllocationsAndNoElementRequestsToIdleAndScrolledFrames() throws {
    let still = try psWindow(scale: 2), residual = try psWindow(scale: 2)
    still.scroll(at: pt(160, 100), byDeltaX: 0, deltaY: -40)
    residual.scroll(at: pt(160, 100), byDeltaX: 0, deltaY: -40.3)
    for w in [still, residual] { for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() } }
    let residues = (try psState(still).residue, try psState(residual).residue)
    #expect(residues.0 == 0 && residues.1 != 0, "one has a residue, one has none: \(residues)")
    func idle(_ w: TestWindow) throws -> (allocations: Int, requests: Int, version: UInt64) {
        let region = try #require(w.window.lastScrollRegions.first)
        let before = w.window.stateTable.entryVersion(region.id)
        var allocations = 0
        #if canImport(Darwin)
        allocations = try #require(countAllocations { w.window.setNeedsRedraw(); w.tick() })
        #else
        w.window.setNeedsRedraw(); w.tick()
        #endif
        return (allocations, w.lastFrameWork.elementRequests, w.window.stateTable.entryVersion(region.id) &- before)
    }
    let a = try idle(still), b = try idle(residual)
    #if canImport(Darwin)
    let pinnedAllocations = 1562
    #else
    let pinnedAllocations = 0   // allocations are counted only where `countAllocations` can (Darwin's malloc zones)
    #endif
    #expect(a.allocations == b.allocations && a.requests == b.requests && a.allocations == pinnedAllocations && a.requests == 43, "idle: \(a) against \(b)")
    #expect(a.version == 0 && b.version == 0, "an idle scroller writes nothing: \(a.version) \(b.version)")
}
