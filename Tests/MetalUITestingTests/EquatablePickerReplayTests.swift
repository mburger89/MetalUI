import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// A downstream app's report: an `.equatable()` panel holding a segmented `Picker` bound to an enum on an `@Observable` model
// drew differently on a frame where the panel was skipped than after a full rebuild.

enum EPShape: CaseIterable { case titled, labelsHidden, inHStack, untitledScrolled }

enum EPMode: String, CaseIterable, Hashable { case one, two, three }

@Observable @MainActor final class EPModel { var mode: EPMode = .one; var query = ""; var tick = 0; var alt = false }

struct EPPanel: Component, @MainActor Equatable {
    let model: EPModel
    let other: EPModel
    var shape: EPShape = .titled
    static func == (l: EPPanel, r: EPPanel) -> Bool { l.model === r.model && l.other === r.other }
    var content: some ElementGroup {
        let picker = Picker(shape == .untitledScrolled ? "" : "Mode", selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
            ForEach(EPMode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) }
        }.pickerStyle(.segmented)
        return VStack(spacing: 4) {
            switch shape {
            case .titled, .untitledScrolled: picker
            case .labelsHidden: picker.labelsHidden()
            case .inHStack: HStack(spacing: 4) { Text("lead"); picker }
            }
            Text("panel")
        }.padding(Edges(all: Pixels(8)))
    }
}

struct EPRoot: Component {
    let model: EPModel
    let other: EPModel
    var shape: EPShape = .titled
    var content: some ElementGroup {
        VStack(spacing: 4) {
            Text("count \(other.tick)")
            TextField("query", text: Binding(get: { other.query }, set: { other.query = $0 }))
            EPPanel(model: model, other: other, shape: shape).equatable()
        }.theme(other.alt ? Theme.dark : Theme.light)
    }
}

@MainActor private func picture(_ w: TestWindow) -> [[Float]] {
    let s = w.scene
    let rects = s.rects.map { [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height,
                               $0.background.h, $0.background.s, $0.background.l, $0.background.a,
                               $0.borderColor.h, $0.borderColor.s, $0.borderColor.l, $0.borderColor.a, $0.borderWidths.top] }
    let glyphs = s.glyphs.map { [$0.bounds.origin.x, $0.bounds.origin.y, $0.color.h, $0.color.s, $0.color.l, $0.color.a] }
    return (rects + glyphs).sorted { $0.lexicographicallyPrecedes($1) }
}

enum EPVariant: CaseIterable { case plain, selectedBefore, selectedByClick, hovering, hoverAfterClick }

@Test(.enabled(if: !rsVerifying, "verify mode paints a hit as a miss"), arguments: EPVariant.allCases, EPShape.allCases) @MainActor
func aSkippedPanelWithASegmentedPickerDrawsWhatARebuildDraws(variant: EPVariant, shape: EPShape) throws {
    let model = EPModel(), other = EPModel()
    let w = try TestWindow(size: sz(300, 120), textSystem: harnessTextSystem) { VStack(spacing: 0) { EPRoot(model: model, other: other, shape: shape) } }
    for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
    switch variant {
    case .plain: break
    case .selectedBefore: model.mode = .two; w.window.setNeedsRedraw(); w.tick()
    case .selectedByClick: try w.click(w.element(label: "three"))
    case .hovering: try w.hover(w.element(label: "two"))
    case .hoverAfterClick: try w.click(w.element(label: "three")); try w.hover(w.element(label: "two"))
    }
    for _ in 0..<2 { w.window.setNeedsRedraw(); w.tick() }
    w.resetFrameWork()
    try w.click(w.element(label: "query")); w.typeText("ab")
    other.tick += 1
    w.window.setNeedsRedraw(); w.tick()
    let skipped = w.frameWork.reduce(FrameWork(), +)
    #expect(skipped.contentSkips > 0, "the panel was skipped: \(skipped.contentSkips)")
    #expect(other.query == "ab", "the query field took the typing: \(other.query)")
    let steady = picture(w)
    // Rebuild everything: another appearance, then back.
    other.alt = true; w.window.setNeedsRedraw(); w.tick()
    #expect(picture(w) != steady, "the other theme draws differently: the rebuild instrument moves")
    other.alt = false; w.window.setNeedsRedraw(); w.tick()
    let rebuilt = picture(w)
    if steady != rebuilt {
        let n = min(steady.count, rebuilt.count)
        let first = (0..<n).first { steady[$0] != rebuilt[$0] }
        Issue.record("counts \(steady.count) vs \(rebuilt.count); first differing index \(String(describing: first)): \(first.map { "\(steady[$0]) vs \(rebuilt[$0])" } ?? "")")
    }
}

/// The retention differential: a retaining window against one with retention off, through a sibling's edits.
@Test(.enabled(if: !rsVerifying, "verify mode paints a hit as a miss"), arguments: EPShape.allCases) @MainActor
func aRetainingWindowWithASegmentedPickerEqualsARetentionOffWindow(shape: EPShape) throws {
    let pair = try RPPair(size: sz(300, 120)) { side in
        let (m, o) = (EPModel(), EPModel())
        return VStack(spacing: 0) { EPRoot(model: m, other: o, shape: shape) }
    }
    for _ in 0..<3 { pair.redraw(); try pair.compare("steady") }
}
