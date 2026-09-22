import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// Lane 4 of `docs/superpowers/specs/2026-09-17-grids-design.md`: a grid through
// the whole pipeline — hit testing, accessibility, paint order and the disabled
// gate (ruling GR-K).
//
// **A grid and a row register and paint nothing of their own**, so every test
// here routes through machinery that already exists and several are GREEN ON
// ARRIVAL. Each one `#require`s a discriminating control first, and each names
// the mutation that reddens its OWN assertion rather than its control's; where
// the mutation is not grid-owned (the disabled gate) it is applied to the shared
// file once and reverted, and the lane records what it reddened.

private func px(_ v: Double) -> Pixels { Pixels(Float(v)) }

@MainActor
private func click(_ platform: FakePlatformWindow, at point: Point<Pixels>) {
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor
private func point(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

@MainActor
private func centre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    Point(x: Pixels(b.origin.x.value + b.size.width.value / 2),
          y: Pixels(b.origin.y.value + b.size.height.value / 2))
}

@MainActor private func drawUntilClean(_ window: Window, limit: Int = 5) {
    for _ in 0..<limit where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// Where each named cell landed, and how often its `onTap` ran.
@MainActor
private final class TapLog {
    var bounds: [String: Bounds<Pixels>] = [:]
    var taps: [String: Int] = [:]
    var gridTaps = 0
}

/// A fixed-size painted cell that records its placed bounds.
private struct TapCell: ProposalElement {
    let name: String
    let log: TapLog
    let width: Double
    let height: Double
    let color: ColorToken

    init(_ name: String, _ log: TapLog, _ width: Double, _ height: Double,
         color: ColorToken = .accent) {
        self.name = name
        self.log = log
        self.width = width
        self.height = height
        self.color = color
    }

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let size = SizeD(width: width, height: height)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log.bounds[name] = bounds
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {
        pass.fill(bounds, color: pass.theme[color])
    }
}

// MARK: - 4.14 a click on a cell

/// **A click at a cell's centre runs that cell's `onTap`, and a click inside its
/// SLOT but outside its frame runs nothing** (ruling GR-K: a cell registers its
/// placed rect, `OM-I`'s default region, not the slot it was aligned in).
///
/// Green on arrival; the control is the cell-centre click, which must count.
///
/// Mutation: place cells at their slot size (the 10×10 cell fills its 40×40 slot
/// and the slot-corner click counts on it).
@MainActor
@Test func aClickOnAGridCellReachesThatCellsOnTap() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = TapLog()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Grid {
            GridRow {
                TapCell("a", log, 40, 40).onTap { log.taps["a", default: 0] += 1 }
                TapCell("b", log, 10, 10).onTap { log.taps["b", default: 0] += 1 }
            }
            GridRow {
                TapCell("c", log, 40, 40).onTap { log.taps["c", default: 0] += 1 }
                TapCell("d", log, 40, 40).onTap { log.taps["d", default: 0] += 1 }
            }
        }
    }
    window.drawFrameIfNeeded()
    let a = try #require(log.bounds["a"])
    let b = try #require(log.bounds["b"])
    for name in ["a", "b", "c", "d"] {
        click(platform, at: centre(try #require(log.bounds[name])))
        window.drawFrameIfNeeded()
    }
    try #require(log.taps == ["a": 1, "b": 1, "c": 1, "d": 1],
                 "control: each centre click counts once on its own cell — \(log.taps)")
    try #require(b.size.width.value == 10 && a.size.width.value == 40,
                 "control: b must be smaller than its slot, or nothing is outside it")

    // Inside column 1's 40pt slot (which starts 8pt past a's trailing edge) but
    // outside b's own 10×10 frame.
    click(platform, at: point(a.origin.x.value + a.size.width.value + 10, a.origin.y.value + 2))
    window.drawFrameIfNeeded()
    #expect(log.taps == ["a": 1, "b": 1, "c": 1, "d": 1],
            "a click in b's slot but outside b counted: \(log.taps)")
}

// MARK: - 4.15 a click in the gap

/// **A click in a grid's gap reaches the grid's own `onTap`, and a cell outranks
/// it** (ruling GR-K: content registers after its container's hitbox, so the
/// cell's ranks above).
///
/// Green on arrival; the control is the gap click, which must reach the grid.
///
/// Mutation: `Grid.prepaint` skips its content's prepaint (no cell hitbox is
/// registered and the cell click reaches the grid, so `gridTaps` reads 2).
@MainActor
@Test func aClickInAGridsGapReachesTheGridsOnTapAndACellOutranksIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = TapLog()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Grid {
            GridRow {
                TapCell("a", log, 40, 40).onTap { log.taps["a", default: 0] += 1 }
                TapCell("b", log, 40, 40).onTap { log.taps["b", default: 0] += 1 }
            }
        }
        .onTap { log.gridTaps += 1 }
    }
    window.drawFrameIfNeeded()
    let a = try #require(log.bounds["a"])
    // The 8pt gap between the two columns.
    click(platform, at: point(a.origin.x.value + a.size.width.value + 4,
                              a.origin.y.value + a.size.height.value / 2))
    window.drawFrameIfNeeded()
    try #require(log.gridTaps == 1, "control: a gap click must reach the grid — \(log.gridTaps)")
    #expect(log.taps.isEmpty, "a gap click also ran a cell: \(log.taps)")

    click(platform, at: centre(a))
    window.drawFrameIfNeeded()
    #expect(log.taps["a"] == 1, "the cell click: \(String(describing: log.taps["a"]))")
    #expect(log.gridTaps == 1, "the cell click also ran the grid: \(log.gridTaps)")
}

// MARK: - 4.16 a grid publishes nothing

/// **A grid publishes nothing to accessibility, and a cell's `onTap` still
/// presses by id** — `AB-Y`'s shape with a grid (ruling GR-K; task 12 owns
/// proposal-path accessibility).
///
/// Green on arrival; the control is that the window actually activated and
/// built a tree.
///
/// Mutation: `GridRow.prepaintGroup` skips its content (the cell registers no
/// hitbox, so the press by id finds nothing and is refused).
@MainActor
@Test func aGridPublishesNothingAndItsCellsTapStillPresses() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = TapLog()
    let (window, platform) = try makeFakeWindow(device: device, size: 200) {
        Grid {
            GridRow {
                TapCell("a", log, 40, 40).onTap { log.taps["a", default: 0] += 1 }
                TapCell("b", log, 40, 40)
            }
        }
    }
    _ = platform.simulateAccessibilityRequest(.activate)
    drawUntilClean(window)
    try #require(window.accessibility.buildCount >= 1, "control: the window was active and built")
    #expect(window.accessibility.lastEmissionCount == 0, "a grid records nothing")
    #expect(window.accessibility.lastPublished.nodes.isEmpty, "a grid publishes nothing")

    let tap = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil }).id
    #expect(platform.simulateAccessibilityRequest(.press(AccessibilityNodeID(tap))))
    #expect(log.taps["a"] == 1, "the press by id: \(String(describing: log.taps["a"]))")
}

// MARK: - 4.18 paint order

/// **A grid paints only its cells, in declaration order**: the grid and its rows
/// emit nothing of their own.
///
/// Each cell is given a distinct size, so its rect is identifiable whatever the
/// order; the assertion is that each appears exactly once and that the four
/// indices increase in row-then-cell order.
///
/// Green on arrival. Mutation: `Grid.paint` paints its content twice (each cell
/// appears twice).
@MainActor
@Test func aGridPaintsOnlyItsCellsInDeclarationOrder() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = TapLog()
    let (window, _) = try makeFakeWindow(device: device, size: 200) {
        Grid {
            GridRow { TapCell("a", log, 41, 11); TapCell("b", log, 21, 21) }
            GridRow { TapCell("c", log, 11, 31); TapCell("d", log, 31, 11) }
        }
    }
    window.drawFrameIfNeeded()
    let rects = window.lastScene.rects
    func indices(_ width: Float, _ height: Float) -> [Int] {
        rects.indices.filter {
            rects[$0].bounds.size.width == width && rects[$0].bounds.size.height == height
        }
    }
    let found = [indices(41, 11), indices(21, 21), indices(11, 31), indices(31, 11)]
    try #require(found.allSatisfy { $0.count == 1 },
                 "each cell must paint exactly once: \(found) of \(rects.count) rects")
    let order = found.map { $0[0] }
    #expect(order == order.sorted(), "cells painted out of declaration order: \(order)")
}

// MARK: - 4.19 the disabled gate reaches every cell

/// **A `.disabled` grid registers no cell hitbox** (ruling GR-K: `.disabled` is
/// an `EnvironmentScope` and the gate is `Frame.registerHandlers`').
///
/// Green on arrival; the enabled control `#require`s one hitbox per tappable
/// cell, so "none" cannot be read off a tree that registered nothing anyway.
///
/// Mutation, NOT grid-owned: drop the disabled gate in `Frame.registerHandlers`'
/// five-argument implementation (shared file, applied once and reverted). Note
/// that `GridRow.prepaintGroup` skipping its content reddens only the control's
/// `#require` and so does not count as this test's mutation.
@MainActor
@Test func aDisabledGridRegistersNoCellHitbox() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    func hitboxes(disabled: Bool) throws -> Int {
        let log = TapLog()
        // `.disabled` is an `EnvironmentScope`, a GROUP, so it is wrapped in a
        // `ZStack` to be a window root; the scope itself is what is under test.
        let (window, _) = try makeFakeWindow(device: device, size: 200) {
            ZStack {
                Grid {
                    GridRow {
                        TapCell("a", log, 40, 40).onTap { log.taps["a", default: 0] += 1 }
                        TapCell("b", log, 40, 40).onTap { log.taps["b", default: 0] += 1 }
                    }
                }
                .disabled(disabled)
            }
        }
        window.drawFrameIfNeeded()
        return window.lastHitboxes.filter { $0.handlers.onClick != nil }.count
    }
    try #require(try hitboxes(disabled: false) == 2, "control: two enabled cells register two hitboxes")
    #expect(try hitboxes(disabled: true) == 0, "a disabled grid registered a cell hitbox")
}
