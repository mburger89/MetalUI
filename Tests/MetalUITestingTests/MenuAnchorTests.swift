import Foundation
import MetalUI
import MetalUITesting
import Observation
import Testing

// XP-G29 (`MA-A`...`MA-F`): a presentation anchor is the label's DRAWN frame in
// window points - scroll, render effects and container origins included - the
// same bounding box the accessibility frame is. PLAIN imports.

private extension Bounds where Unit == Pixels {
    var bottom: Float { origin.y.value + size.height.value }
    var centerX: Float { origin.x.value + size.width.value / 2 }
    var centerY: Float { origin.y.value + size.height.value / 2 }
}

/// A model whose offset a test moves.
@Observable @MainActor private final class AnchorModel {
    var dx: Float = 60
    var dy: Float = 40
}

/// The label's drawn box, and where the platform was asked to pop the menu.
@MainActor private func expectNativeAnchor(_ window: TestWindow, label text: String = "View",
                                           sourceLocation: SourceLocation = #_sourceLocation) throws {
    let label = try window.element(label: text)
    try window.click(label)
    let shown = try #require(window.platformWindow.presentedMenus.last, sourceLocation: sourceLocation)
    #expect(abs(shown.at.x.value - label.frame.origin.x.value) < 1.01,
            "x is the drawn label's: \(shown.at) vs \(label.frame)", sourceLocation: sourceLocation)
    #expect(abs(shown.at.y.value - (label.frame.bottom)) < 1.01,
            "y is the drawn label's bottom: \(shown.at) vs \(label.frame)", sourceLocation: sourceLocation)
}

@MainActor private func viewMenu() -> some Element {
    Menu("View") {
        Button("Perspective") {}
        Button("Orthographic") {}
    }
}

/// T1 - the repro: a pane that does not start at the window origin, `.offset`.
@MainActor private func offsetMenuTree() -> some Element {
    HStack(spacing: 0) {
        Color.clear.frame(width: Pixels(120))
        VStack(alignment: .leading, spacing: 4) {
            Button("Home") {}
            viewMenu()
        }
        .offset(x: Pixels(60), y: Pixels(40))
    }
}

@Test @MainActor func aMenuUnderOffsetPresentsAtItsDrawnLabel() throws {
    let window = try harnessWindow { offsetMenuTree() }
    try expectNativeAnchor(window)
    // Separating arm: the drawn label is away from its layout position.
    #expect(try window.element(label: "View").frame.origin.x.value >= 180)
}

/// T2 - a split pane with a non-zero origin under `.offset` and `.scaleEffect`, both nestings.
@Test @MainActor func aMenuInAPaneUnderOffsetAndScaleAnchorsToTheDrawnBox() throws {
    let a = try harnessWindow {
        HStack(spacing: 0) {
            Color.clear.frame(width: Pixels(120))
            VStack(alignment: .leading, spacing: 4) { Button("Home") {}; viewMenu() }
                .offset(x: Pixels(30), y: Pixels(20))
                .scaleEffect(1.5, anchor: .topLeading)
        }
    }
    try expectNativeAnchor(a)
    let b = try harnessWindow {
        HStack(spacing: 0) {
            Color.clear.frame(width: Pixels(120))
            VStack(alignment: .leading, spacing: 4) { Button("Home") {}; viewMenu() }
                .scaleEffect(1.5, anchor: .topLeading)
                .offset(x: Pixels(30), y: Pixels(20))
        }
    }
    try expectNativeAnchor(b)
}

/// T2b - MetalCreator's shape: a large model offset, an overlay over a `GPUSurface` in the right pane of a split.
@Test @MainActor func aMenuUnderMetalCreatorsShapeAnchorsToTheDrawnBox() throws {
    let model = AnchorModel()
    model.dx = 990
    model.dy = 310
    let window = try harnessWindow(size: sz(1200, 700)) {
        HStack(spacing: 0) {
            VStack(spacing: 0) { Text("graph").frame(width: Pixels(300), height: Pixels(100)) }
                .frame(width: Pixels(200))
            GPUSurface(redraw: .onDemand, value: 0) { _ in }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) { Button("A") {}; Button("B") {}; Button("C") {} }
                        viewMenu()
                    }
                    .offset(x: Pixels(model.dx - 200), y: Pixels(model.dy))
                }
        }
    }
    let label = try window.element(label: "View")
    try expectNativeAnchor(window)
    let shown = try #require(window.platformWindow.presentedMenus.last)
    #expect(shown.at.x.value > 600 && shown.at.y.value > 300, "far from the layout origin: \(shown.at), label \(label.frame)")
}

/// T3 - a rotated label anchors to its bounding box (`MA-B`'s approximation).
@Test @MainActor func aMenuUnderRotationAnchorsToTheBoundingBoxCorner() throws {
    let window = try harnessWindow {
        VStack { viewMenu() }.rotationEffect(.degrees(30), anchor: .topLeading).offset(x: Pixels(80), y: Pixels(60))
    }
    try expectNativeAnchor(window)
}

/// T4 - scroll plus `.offset`: the scroll translation counts once.
@Test @MainActor func aMenuInAScrolledScrollViewUnderOffsetAnchorsToTheDrawnBox() throws {
    let window = try harnessWindow {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(width: Pixels(100), height: Pixels(120))
                VStack { viewMenu() }.offset(x: Pixels(40), y: Pixels(20))
                Color.clear.frame(width: Pixels(100), height: Pixels(600))
            }
        }
    }
    window.scroll(at: pt(200, 150), byDeltaX: 0, deltaY: -50)
    window.tick()
    try expectNativeAnchor(window)
}

/// T5 - an `.equatable()` component replays its anchor on an unchanged key and re-anchors when the offset moves.
private struct EqMenu: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 4) { Button("Home") {}; Menu("View") { Button("Perspective") {} } }
    }
    static func == (l: EqMenu, r: EqMenu) -> Bool { true }
}

@Test @MainActor func aMenuInAnEquatableComponentReplaysItsAnchor() async throws {
    let model = AnchorModel()
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Color.clear.frame(width: Pixels(100))
            VStack { EqMenu().equatable() }.offset(x: Pixels(model.dx), y: Pixels(model.dy))
        }
    }
    try expectNativeAnchor(window)
    var hits = 0
    for _ in 0..<3 { window.tick(); hits += window.lastFrameWork.retainedPrepaintHits }
    try expectNativeAnchor(window)
    #expect(hits >= 0, "replay frames ran: \(hits)")
    model.dx = 10
    model.dy = 90
    try await window.runUntilIdle()
    window.tick()
    try expectNativeAnchor(window)
    #expect(try window.element(label: "View").frame.origin.x.value < 140, "moved")
}

/// T6 - `.pickerStyle(.menu)`.
@Test @MainActor func aPickerMenuUnderOffsetAnchorsToTheDrawnBox() throws {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Color.clear.frame(width: Pixels(100))
            VStack { PickerFixture() }.offset(x: Pixels(50), y: Pixels(35))
        }
    }
    let label = try #require(window.elements(role: .popUpButton).first)
    try window.click(label)
    let shown = try #require(window.platformWindow.presentedMenus.last)
    #expect(abs(shown.at.x.value - label.frame.origin.x.value) < 1.01, "\(shown.at) vs \(label.frame)")
    #expect(abs(shown.at.y.value - label.frame.bottom) < 1.01, "\(shown.at) vs \(label.frame)")
}

private struct PickerFixture: Component {
    @State var mode = 0
    var content: some ElementGroup {
        Picker("Mode", selection: $mode) {
            Text("One").tag(0)
            Text("Two").tag(1)
        }
        .pickerStyle(.menu)
    }
}

/// T7 - a keyboard / accessibility opened context menu uses the drawn box; a pointer-opened one the press point.
@Test @MainActor func aKeyboardOpenedContextMenuUnderOffsetAnchorsToTheDrawnBox() throws {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            Color.clear.frame(width: Pixels(100))
            Button("Target") {}
                .contextMenu { Button("Copy") {} }
                .frame(width: Pixels(80), height: Pixels(24))
                .offset(x: Pixels(70), y: Pixels(50))
        }
    }
    let target = try window.element(label: "Target")
    #expect(try window.performAccessibilityAction(.showMenu, on: target))
    let shown = try #require(window.platformWindow.presentedMenus.last)
    #expect(abs(shown.at.x.value - target.frame.origin.x.value) < 1.01, "\(shown.at) vs \(target.frame)")
    #expect(abs(shown.at.y.value - target.frame.bottom) < 1.01, "\(shown.at) vs \(target.frame)")
    try window.dismissMenu()
    try window.rightClick(target)
    let pressed = try #require(window.platformWindow.presentedMenus.last)
    #expect(abs(pressed.at.x.value - target.frame.centerX) < 1.01 && abs(pressed.at.y.value - target.frame.centerY) < 1.01,
            "pointer open stays at the press: \(pressed.at)")
}

/// T8 - a popover places from the drawn box: its panel moves with the offset.
@Test @MainActor func aPopoverAndAnchoredOverlayUnderOffsetPlaceFromTheDrawnBox() throws {
    @MainActor func panelOrigin(offset: Bool) throws -> Point<Pixels> {
        let window = try harnessWindow {
            HStack(spacing: 0) {
                Color.clear.frame(width: Pixels(100))
                VStack {
                    Button("Open") {}
                        .popover(isPresented: .constant(true)) {
                            Text("Panel").frame(width: Pixels(60), height: Pixels(20))
                        }
                }
                    .offset(x: Pixels(offset ? 40 : 0), y: Pixels(offset ? 30 : 0))
            }
        }
        window.tick()
        return try window.element(label: "Panel").frame.origin
    }
    let plain = try panelOrigin(offset: false)
    let moved = try panelOrigin(offset: true)
    #expect(abs((moved.x.value - plain.x.value) - 40) < 1.01, "x follows the offset: \(plain) -> \(moved)")
    #expect(abs((moved.y.value - plain.y.value) - 30) < 1.01, "y follows the offset: \(plain) -> \(moved)")
}

/// T9 - the drawn menu (SDL's answer) opens at the drawn label.
@Test @MainActor func aDrawnMenuOpensAtTheDrawnLabelUnderOffset() throws {
    let window = try harnessWindow(options: .init(presentsMenusNatively: false)) { offsetMenuTree() }
    let label = try window.element(label: "View")
    try window.click(label)
    let items = try window.elements { $0.role == .menuItem }
    let first = try #require(items.first)
    #expect(abs(first.frame.origin.x.value - label.frame.origin.x.value) < 8, "\(first.frame) vs \(label.frame)")
    #expect(first.frame.origin.y.value >= label.frame.bottom - 1, "below the drawn label: \(first.frame) vs \(label.frame)")
    #expect(first.frame.origin.y.value < label.frame.bottom + 12, "next to the drawn label: \(first.frame) vs \(label.frame)")
}

/// T10 - a legacy element's own `.offset` is in the anchor too (`MA-B`).
@Test @MainActor func aLegacyElementsOwnEffectIsInTheAnchor() throws {
    let window = try harnessWindow {
        Column {
            Menu("View") { Button("Perspective") {} }.offset(x: Pixels(55), y: Pixels(25))
        }
    }
    try expectNativeAnchor(window)
}

/// T11 - the one function: no other site builds a presentation or context-menu bounds.
@Test func everyPresentationBoundsSiteGoesThroughTheOneFunction() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/MetalUI/Frame.swift")
    let source = try String(contentsOf: url, encoding: .utf8)
    func window(after marker: String, length: Int = 420) throws -> [Substring] {
        var out: [Substring] = []
        var from = source.startIndex
        while let r = source.range(of: marker, range: from..<source.endIndex) {
            out.append(source[r.lowerBound..<(source.index(r.lowerBound, offsetBy: length, limitedBy: source.endIndex) ?? source.endIndex)])
            from = r.upperBound
        }
        return out
    }
    let anchors = try window(after: "func recordPresentationAnchor")
    #expect(anchors.count == 1)
    for body in anchors {
        #expect(body.contains("presentationWindowBounds("), "recordPresentationAnchor routes through the function")
        #expect(!body.contains("activeOffset"), "and does no offset arithmetic of its own")
    }
    let records = try window(after: "ContextMenuRecord(")
    #expect(!records.isEmpty)
    for body in records {
        #expect(body.contains("presentationWindowBounds("), "ContextMenuRecord's bounds go through the function")
        #expect(!body.contains("activeOffset"))
    }
}
