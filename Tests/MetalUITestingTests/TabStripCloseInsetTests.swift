import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// The close X sits inside the selected tab's shape (`TBS-R`, record 429). Plain imports, headless `TestWindow`, the portable
// harness text system. The X's frame is the 16 x 16 hover-wash rect (drawn, clear, behind the glyph) and the fill is the one
// green rect the selected tab paints; both are read from the scene, so what is checked is what is laid out.

@MainActor private final class InsetModel {
    var selected = "a"
    var closed: [String] = []
    var binding: Binding<String> { Binding(get: { self.selected }, set: { self.selected = $0 }) }
}

private let insetGreen = Hsla(h: 1.0 / 3, s: 1, l: 0.5, a: 1)

@MainActor private func insetWindow(_ m: InsetModel, shape: TabStripSelectionShape, titles: [String] = ["main.swift", "b.swift"],
                                    width: Float = 800) throws -> TestWindow {
    let items = titles.enumerated().map { TabStripItem(id: ["a", "b", "c"][$0.offset], title: $0.element) }
    let window = try harnessWindow(size: sz(width, 100)) {
        VStack(spacing: 0) {
            TabStrip(selection: m.binding, tabs: items)
                .selectedTabShape(shape)
                .selectedTabFill(.color(Color(red: 0, green: 1, blue: 0)))
                .onCloseTab { m.closed.append($0) }
            Spacer()
        }
    }
    window.tick()
    window.tick()
    return window
}

/// The selected tab's fill rect (the green one) and the close X's 16 x 16 frame.
@MainActor private func fillAndX(_ window: TestWindow) throws -> (fill: MUIRect, x: MUIBounds) {
    let fills = window.scene.rects.filter { abs($0.background.h - insetGreen.h) < 0.005 && $0.background.a > 0 && $0.bounds.size.width < 400 }
    try #require(fills.count == 1, "one green fill: \(fills.count)")
    let xs = window.scene.rects.filter { $0.bounds.size.width == 16 && $0.bounds.size.height == 16 }
    try #require(xs.count == 1, "one close X: \(xs.count)")
    return (fills[0], xs[0].bounds)
}

/// Whether `point` lies inside `bounds` rounded by `radius`, with `clearance` to spare from the curve and the edges.
private func inside(_ px: Float, _ py: Float, bounds b: MUIBounds, radius: Float, clearance: Float) -> Bool {
    let left = b.origin.x + clearance, right = b.origin.x + b.size.width - clearance
    let top = b.origin.y + clearance, bottom = b.origin.y + b.size.height - clearance
    let r = max(radius - clearance, 0)
    guard px >= left, px <= right, py >= top, py <= bottom else { return false }
    let dx = max(left + r - px, px - (right - r), 0), dy = max(top + r - py, py - (bottom - r), 0)
    return (dx * dx + dy * dy).squareRoot() <= r + 0.001
}

@MainActor private func assertXInside(_ shape: TabStripSelectionShape, radius: Float) throws {
    let window = try insetWindow(InsetModel(), shape: shape)
    let (fill, x) = try fillAndX(window)
    let corners = [(x.origin.x, x.origin.y), (x.origin.x + x.size.width, x.origin.y),
                   (x.origin.x, x.origin.y + x.size.height), (x.origin.x + x.size.width, x.origin.y + x.size.height)]
    #expect(fill.cornerRadii.topLeft == radius, "the fill's radius \(fill.cornerRadii.topLeft)")
    for (cx, cy) in corners {
        #expect(inside(cx, cy, bounds: fill.bounds, radius: fill.cornerRadii.topLeft, clearance: 2),
                "corner (\(cx), \(cy)) of the X \(x) is not 2 points inside the fill \(fill.bounds) r=\(fill.cornerRadii.topLeft)")
    }
}

/// 1 - the capsule's X frame lies inside the pill with 2 points to spare. Mutation: **M1** a trailing inset of 0 (the close
/// slot at the cell's edge) puts the frame's right corners 8 points past the curve and reddens it.
@Test @MainActor func theCapsulesCloseXLiesInsideThePill() throws {
    try assertXInside(.capsule, radius: 11.5)
}

/// 2 - the same for a rounded rectangle (radius 6, and a radius too small to reach the X's corners). Mutation: **M1**.
@Test @MainActor func aRoundedRectanglesCloseXLiesInsideIt() throws {
    try assertXInside(.roundedRectangle(radius: 6), radius: 6)
    try assertXInside(.roundedRectangle(radius: 2), radius: 2)
}

/// 3 - `.rectangle` keeps today's spacing: the X's frame ends 1 point inside the cell's trailing edge (the slot is 18 wide
/// and the X centred in it), which is the tab label's frame plus the slot. Mutation: **M2** the inset applied to `.rectangle`.
@Test @MainActor func theRectanglesCloseXIsWhereItWas() throws {
    let window = try insetWindow(InsetModel(), shape: .rectangle)
    let label = try window.element(label: "main.swift").frame
    let x = try fillAndXRectangle(window)
    #expect(x.origin.x + x.size.width == label.origin.x.value + label.size.width.value + 17, "\(x) \(label)")
    #expect(x.origin.x == label.origin.x.value + label.size.width.value + 1, "\(x)")
}

@MainActor private func fillAndXRectangle(_ window: TestWindow) throws -> MUIBounds {
    let xs = window.scene.rects.filter { $0.bounds.size.width == 16 && $0.bounds.size.height == 16 }
    try #require(xs.count == 1, "one close X: \(xs.count)")
    return xs[0].bounds
}

/// 4 - every tab of a shaped strip has the inset, the selected or not: the unselected tab's cell is as much wider than a
/// rectangle strip's as the selected one's, so the X does not move when the selection does. The inset is 10 for the capsule and
/// 6 for `roundedRectangle(6)`. Mutation: **M3** the inset only when `isSelected`.
@Test @MainActor func everyTabCarriesTheInsetAndItGrowsTheCellByIt() throws {
    let long = "a-fairly-long-file-name.swift"
    func offsets(_ shape: TabStripSelectionShape) throws -> [Float] {
        let window = try insetWindow(InsetModel(), shape: shape, titles: [long, long + "2", long + "3"], width: 1000)
        let frames = try [long, long + "2", long + "3"].map { try window.element(label: $0).frame }
        return frames.map { $0.origin.x.value }
    }
    let plain = try offsets(.rectangle), capsule = try offsets(.capsule), rounded = try offsets(.roundedRectangle(radius: 6))
    // Tab n starts after n tabs of 18 (slot) + label; each shaped tab is wider by its inset, selected or not.
    #expect(capsule[1] - capsule[0] == plain[1] - plain[0] + 10, "\(plain) \(capsule)")
    #expect(capsule[2] - capsule[1] == plain[2] - plain[1] + 10, "the unselected tab too: \(plain) \(capsule)")
    #expect(rounded[1] - rounded[0] == plain[1] - plain[0] + 6, "\(plain) \(rounded)")
    #expect(rounded[2] - rounded[1] == plain[2] - plain[1] + 6, "\(plain) \(rounded)")
}

/// 5 - a tab at the maximum width still truncates its title and still holds the X inside the pill: the cell stays 220 wide,
/// the label gives up the inset. Mutation: **M4** put the inset on the cell after the width clamp (the X lands outside).
@Test @MainActor func aTabAtTheMaximumWidthTruncatesAndKeepsTheXInside() throws {
    let title = String(repeating: "very-long-file-name-", count: 6) + ".swift"
    let window = try insetWindow(InsetModel(), shape: .capsule, titles: [title])
    let label = try window.element(label: title).frame
    let (fill, x) = try fillAndX(window)
    #expect(fill.bounds.size.width == 220 - 6, "the cell is 220 wide, the pill 3 points in on each side: \(fill.bounds)")
    #expect(label.size.width.value == 220 - 18 - 10, "the label gave up slot and inset: \(label)")
    #expect(inside(x.origin.x + x.size.width, x.origin.y, bounds: fill.bounds, radius: 11.5, clearance: 2))
}

/// 6 - a click on the X's new position closes the tab; a click in the cell's last 2 points does not (and nor does one in the
/// inset between the X and the cell's edge). Mutation: **M5** the inset inside the slot (the hit target grows with it).
@Test @MainActor func theCloseTargetMovesWithTheX() throws {
    for shape in [TabStripSelectionShape.capsule, .roundedRectangle(radius: 6)] {
        let m = InsetModel()
        let window = try insetWindow(m, shape: shape)
        let (_, x) = try fillAndX(window)
        let label = try window.element(label: "main.swift").frame
        let cellRight = label.origin.x.value + label.size.width.value + 18 + (shape == .capsule ? 10 : 6)
        #expect(x.origin.x + x.size.width == cellRight - (shape == .capsule ? 10 : 6) - 1, "the X is 1 inside the slot: \(x)")
        window.hover(at: pt(cellRight - 1, 16)); window.tick()
        window.click(at: pt(cellRight - 1, 16)); window.tick()
        window.click(at: pt(cellRight - 2, 16)); window.tick()
        #expect(m.closed.isEmpty, "the last 2 points close nothing: \(m.closed)")
        let centre = pt(x.origin.x + x.size.width / 2, x.origin.y + x.size.height / 2)
        window.hover(at: centre); window.tick()
        window.click(at: centre); window.tick()
        #expect(m.closed == ["a"], "a click on the X closes the tab: \(m.closed)")
    }
}
