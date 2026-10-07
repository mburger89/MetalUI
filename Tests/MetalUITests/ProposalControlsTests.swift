import Foundation
import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// Spec `docs/superpowers/specs/2026-10-06-proposal-controls-design.md` §6.1,
// tests 1.1, 1.4–1.8, 1.10–1.20 and 1.22 (lane 1; 1.9 and 1.23 are lane 2's,
// `GreedyControlSizingTests.swift`, and 1.2, 1.3, 1.21 are typecheck guards in
// `ProposalControlsCompileGuards.swift`). Rulings `PE-B` (the builder), `PE-C`
// (`LegacyContent`), `PE-D` (greedy sizing), `PE-F` (proposal-only modifiers on
// legacy content), `PE-I` (what does not move), `PE-Q`, `PE-S` in
// `docs/superpowers/2026-10-06-proposal-controls-decisions.md`.
//
// Every SwiftUI number named here comes from the probe
// `docs/probes/swiftui-controls-in-stacks.swift` (its READING); every MetalUI
// literal from spec §1.3's table, measured by the design session through the
// same adapter semantics before this lane, or — where the spec says "measured
// by the lane" — named as such. Helpers are `ButtonTests.swift`'s `control…`
// and `LayoutDifferential`'s harness (root `[0]`, its content `[0, 0]`).
//
// Window tests drive `drawFrameIfNeeded`, `simulateInput` and `simulateTick`;
// nothing sleeps.

// MARK: - Shared helpers

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func near(_ a: Double, _ b: Double) -> Bool {
    a == b || abs(a - b) < 0.01
}

private func near(_ a: Float, _ b: Float) -> Bool { near(Double(a), Double(b)) }

/// The probe's six proposals, by spec §1.3's column names.
private let probeProposals: [(String, ProposedSize)] = [
    ("zero", ProposedSize(width: 0, height: 0)),
    ("ideal", ProposedSize(width: nil, height: nil)),
    ("inf", ProposedSize(width: .infinity, height: .infinity)),
    ("w200", ProposedSize(width: 200, height: nil)),
    ("h200", ProposedSize(width: nil, height: 200)),
    ("w50", ProposedSize(width: 50, height: nil)),
]

/// One child's answers, recorded by `Ask`.
private final class Answers: @unchecked Sendable {
    var sizes: [String: SizeD] = [:]
}

/// A recording layout: measures its one subview at every probe proposal, then
/// answers and places it at its own proposal.
private struct Ask: ProposalLayout {
    let answers: Answers

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        for (name, offer) in probeProposals {
            answers.sizes[name] = subviews[0].sizeThatFits(offer).size
        }
        return subviews[0].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), proposal: proposal)
    }
}

/// `control`'s answers inside `ProposalLayoutContainer(Ask())` — the legacy
/// control adopted by `ProposalContentBuilder` (`PE-B`) — with the report
/// required empty.
@MainActor
private func answers<E: ElementGroup>(_ control: E) throws -> [String: SizeD] {
    let answers = Answers()
    let frame = LayoutDifferential.render(width: 400, height: 300) {
        ProposalLayoutContainer(Ask(answers: answers)) { control }
    }
    try #require(frame.unlowerableFields.isEmpty, "the fixture reported \(frame.unlowerableFields)")
    try #require(answers.sizes.count == probeProposals.count, "Ask measured \(answers.sizes.keys.sorted())")
    return answers.sizes
}

/// A `(width, height)` pair; `.infinity` where the answer is infinite.
private typealias WH = (Double, Double)

/// Asserts `got` against six expected answers, in `probeProposals`' order.
private func expectRow(_ name: String, _ got: [String: SizeD], _ expected: [WH],
                       sourceLocation: SourceLocation = #_sourceLocation) {
    for ((proposal, _), (w, h)) in zip(probeProposals, expected) {
        guard let size = got[proposal] else {
            Issue.record("\(name) \(proposal): no answer", sourceLocation: sourceLocation)
            continue
        }
        #expect(near(size.width, w) && near(size.height, h),
                "\(name) at \(proposal): \(size.width)×\(size.height), expected \(w)×\(h)",
                sourceLocation: sourceLocation)
    }
}

private func six(_ wh: WH) -> [WH] { Array(repeating: wh, count: 6) }

/// The id at `path` under the harness's root.
private func id(_ path: Int...) -> GlobalElementID { controlID(path) }

private func xywh(_ b: Bounds<Pixels>) -> [Float] {
    [b.origin.x.value, b.origin.y.value, b.size.width.value, b.size.height.value]
}

private func expectFrame(_ bounds: [GlobalElementID: Bounds<Pixels>], _ id: GlobalElementID,
                         _ expected: [Float], _ name: String,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    guard let b = bounds[id] else {
        Issue.record("\(name): \(id) recorded no bounds", sourceLocation: sourceLocation)
        return
    }
    let got = xywh(b)
    #expect(zip(got, expected).allSatisfy { near($0, $1) }, "\(name): \(got), expected \(expected)",
            sourceLocation: sourceLocation)
}

private struct Item: Identifiable, Hashable, Sendable {
    let id: Int
}

private let longLabel = "A much longer label"

// MARK: - 1.1 every control's class

/// **1.1** (`PE-B`, `PE-D`, `PE-N`, `PE-Q`). Every control inside a proposal
/// container answers the probe's six proposals as spec §1.3's table (after
/// `PE-D`) says, to 0.01 — each row's class is SwiftUI's (probe FL arm named);
/// the metrics and the below-ideal arms are MetalUI's own (divergences 130,
/// 131), and `List(selection:)` keeps divergence 84's `rowHeight × count`.
///
/// Red before: does not compile (legacy content in a proposal container).
/// Mutations: M1.1a (`TextField`'s infinite answer reverted) reddens its `inf`
/// arm; M1.1b (`Toggle`'s label gap + 1) its `ideal` arm — a non-`PE-D` arm can
/// fail.
@Test @MainActor func everyControlAnswersInSwiftUIsClassInsideAProposalContainer() throws {
    // FX3 / FL1-text: wraps per `ProposalText` (`PE-G`), divergence 60's widths.
    expectRow("Text(Go)", try answers(Text("Go")),
              [(0, 16), (17.23, 16), (17.23, 16), (17.23, 16), (17.23, 16), (17.23, 16)])
    expectRow("Text(long)", try answers(Text(longLabel)),
              [(0, 16), (120.12, 16), (120.12, 16), (120.12, 16), (120.12, 16), (49.36, 48)])
    // FL0: hugs. Below its ideal it keeps its strut and padding (divergence 130).
    expectRow("Button(Go)", try answers(Button("Go") {}),
              [(24, 24), (41.23, 24), (41.23, 24), (41.23, 24), (41.23, 24), (41.23, 24)])
    // FL15: `.plain` hugs its label.
    expectRow("Button.plain", try answers(Button("Go") {}.buttonStyle(.plain)),
              [(0, 16), (17.23, 16), (17.23, 16), (17.23, 16), (17.23, 16), (17.23, 16)])
    // FL2: hugs, wraps its label at 50 (SwiftUI 43×32).
    expectRow("Toggle(Wi-Fi)", try answers(Toggle("Wi-Fi", isOn: .constant(false))),
              [(21, 16), (53.20, 16), (53.20, 16), (53.20, 16), (53.20, 16), (42.70, 32)])
    // FL3: greedy width (`PE-D`); one line tall and the placeholder + 1 (divergence 131).
    expectRow("TextField(Name) empty", try answers(TextField("Name", text: .constant(""))),
              [(0, 16), (36.25, 16), (.infinity, 16), (200, 16), (36.25, 16), (50, 16)])
    // FL5: greedy on both axes (`PE-D`).
    expectRow("TextEditor(Hello)", try answers(TextEditor(text: .constant("Hello"))),
              [(0, 0), (31.95, 16), (.infinity, .infinity), (200, 16), (31.95, 200), (50, 16)])
    // FL6: greedy width (`PE-D`), 30 at nil.
    expectRow("Slider", try answers(Slider(value: .constant(0.5))),
              [(0, 16), (30, 16), (.infinity, 16), (200, 16), (30, 16), (50, 16)])
    // FL7: hugs.
    expectRow("Stepper(Qty)", try answers(Stepper("Qty", value: .constant(1), in: 0...3)),
              [(28, 24), (49.58, 24), (49.58, 24), (49.58, 24), (49.58, 24), (49.58, 24)])
    // FL8–FL10: every Picker style hugs.
    func picker() -> Picker<Int, Pair<TaggedElement<Text>, TaggedElement<Text>>> {
        Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }
    }
    expectRow("Picker.menu", try answers(picker().pickerStyle(.menu)),
              [(67, 24), (112.56, 24), (112.56, 24), (112.56, 24), (112.56, 24), (67, 64)])
    expectRow("Picker.segmented", try answers(picker().pickerStyle(.segmented)),
              [(124.85, 24), (159.00, 24), (159.00, 24), (159.00, 24), (159.00, 24), (124.85, 64)])
    expectRow("Picker.radioGroup", try answers(picker().pickerStyle(.radioGroup)),
              [(29, 38), (97.57, 38), (97.57, 38), (97.57, 38), (97.57, 38), (50, 150)])
    // FL11: greedy along a stack's cross axis (here: no stack, so both readings).
    expectRow("Divider", try answers(Divider()),
              [(0, 1), (10, 1), (.infinity, 1), (200, 1), (10, 1), (50, 1)])
    // FL13: hugs; wraps its label at 50 (divergence 130).
    expectRow("Menu(Actions)", try answers(Menu("Actions") { Button("One") {} }),
              [(24, 24), (80.66, 24), (80.66, 24), (80.66, 24), (80.66, 24), (49.64, 64)])
    // FL16, FL17: a legacy `.padding(8)` adds 16 a side pair; `.frame(width:)` fixes.
    expectRow("Button.padding(8)", try answers(Button("Go") {}.padding(px(8))),
              [(40, 40), (57.23, 40), (57.23, 40), (57.23, 40), (57.23, 40), (49.63, 48)])
    expectRow("Button.frame(width: 120)", try answers(Button("Go") {}.frame(width: px(120))),
              six((120, 24)))
    // FL21: a flexible frame makes a hugging control greedy.
    expectRow("Toggle.frame(maxWidth: .infinity)",
              try answers(Toggle("Wi-Fi", isOn: .constant(false)).frame(maxWidth: .infinity)),
              [(21, 16), (53.20, 16), (.infinity, 16), (200, 16), (53.20, 16), (50, 32)])
    // FL18: `.disabled` changes nothing.
    expectRow("Button.disabled(true)", try answers(Button("Go") {}.disabled(true)),
              [(24, 24), (41.23, 24), (41.23, 24), (41.23, 24), (41.23, 24), (41.23, 24)])
    // FL14: SwiftUI's list is greedy on both axes; MetalUI's answers its
    // windowing contract, `rowHeight × count` (divergence 84, `PE-Q`); its
    // width is its rows' (37.26, "Row 0" … "Row 2") at nil and greedy at an
    // infinite offer — measured by the lane, as `PE-Q` asks.
    let items = (0..<3).map(Item.init)
    expectRow("List(selection:) 3 rows",
              try answers(List(items, selection: .constant(Int?.none), rowHeight: px(20)) { item in
                  Text("Row \(item.id)")
              }),
              [(0, 60), (37.26, 60), (.infinity, 60), (200, 60), (37.26, 60), (50, 60)])
}

// MARK: - 1.4 identity

/// A `Component` holding `@State`, read back through a box `10 + 10 × count` wide.
private struct Counter: Component {
    @State var count = 0
    var content: some ElementGroup {
        Button("+") { count += 1 }
        Box().frame(width: px(10 + 10 * Float(count)), height: px(7))
    }
}

@MainActor private final class Flag {
    var on = false
}

/// **1.4** (`PE-C` item 1). In `HStack { Rectangle(); Button; Toggle }` the
/// Button's id is `.child(of: hstack, at: 1)` and the Toggle's `at: 2` — the
/// ids two `Rectangle`s take there; a legacy `Component` with `@State` in a
/// `VStack` keeps its value across three frames and across an `if` toggling a
/// sibling before it (the `if` takes one slot either way, `ID-B`).
///
/// Red before: does not compile. Mutations: M1.4a (`LegacyContent` passes a
/// fresh cursor) collides the ids; M1.4b (it enters a group member level) shifts
/// them.
@Test @MainActor func aLegacyControlTakesTheIDAProposalElementWouldInItsPosition() throws {
    let mixed = LayoutDifferential.report(width: 400, height: 100) {
        HStack {
            Rectangle(width: px(10), height: px(10))
            Button("b") {}
            Toggle("t", isOn: .constant(true))
        }
    }
    try #require(mixed.unlowerable.isEmpty, "\(mixed.unlowerable)")
    let proposal = LayoutDifferential.report(width: 400, height: 100) {
        HStack {
            Rectangle(width: px(10), height: px(10))
            Rectangle(width: px(10), height: px(10))
            Rectangle(width: px(10), height: px(10))
        }
    }
    let hstack = id(0, 0)
    for index in 0..<3 {
        let child = GlobalElementID.child(of: hstack, at: index, name: nil)
        #expect(mixed.bounds[child] != nil, "the mixed stack's child \(index) is \(child)")
        #expect(proposal.bounds[child] != nil, "the proposal stack's child \(index) is \(child)")
    }
    // The Button's label is its own child; the toggle sits after it, not inside.
    let button = try #require(mixed.bounds[id(0, 0, 1)])
    let toggle = try #require(mixed.bounds[id(0, 0, 2)])
    #expect(toggle.origin.x.value >= button.origin.x.value + button.size.width.value,
            "the Toggle is the Button's next sibling: \(button) \(toggle)")
    #expect(mixed.bounds[id(0, 0, 3)] == nil, "no fourth slot")

    let flag = Flag()
    let (window, platform) = try controlWindow {
        VStack {
            if flag.on { Text("sibling") }
            Counter()
        }
    }
    let plus = try controlBounds(window.lastFrameBounds(), id(0, 1, 0))
    let bar = id(0, 1, 1)
    #expect(window.lastElementBounds[bar]?.size.width.value == 10, "count 0")
    controlClick(platform, at: controlCentre(plus))
    for _ in 0..<3 { controlRedraw(window) }
    #expect(window.lastElementBounds[bar]?.size.width.value == 20, "count 1 across three frames")
    flag.on = true
    controlRedraw(window)
    #expect(window.lastElementBounds[bar]?.size.width.value == 20, "count 1 with the sibling shown")
    flag.on = false
    controlRedraw(window)
    #expect(window.lastElementBounds[bar]?.size.width.value == 20, "count 1 with the sibling hidden again")
    withExtendedLifetime(window) {}
}

// MARK: - 1.5, 1.6 the form and the status bar

/// **1.5** (`PE-B`, `PE-D`; probe FM0). FM0 in SwiftUI's spelling at 400×300:
/// spec §1.3's "after `PE-D`" literals, and the probe's relations — the trailing
/// `Button` at 384, the `TextField`/`Slider` taking 368 − label − 8, the
/// `Divider` 368. Diagnostics pre-flighted empty.
///
/// Red before: does not compile; at runtime (through the adapter) the slider is
/// 180. Mutation M1.5 (`Slider`'s `PE-D` reverted) → 180.
@Test @MainActor func aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt() throws {
    let report = LayoutDifferential.report(width: 400, height: 300) {
        VStack(alignment: .leading) {
            HStack {
                Text("Name")
                TextField("Name", text: .constant(""))
            }
            HStack {
                Toggle("Enabled", isOn: .constant(true))
                Spacer()
                Button("Apply") {}
            }
            HStack {
                Text("Speed")
                Slider(value: .constant(0.5))
            }
            Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }
                .pickerStyle(.menu)
            Divider()
            HStack {
                Stepper("Qty", value: .constant(1), in: 0...3)
                Spacer()
            }
        }
        .padding(Edges(all: px(16))).frame(width: px(400)).fixedSize(horizontal: false, vertical: true)
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let b = report.bounds
    // Three proposal layers (fixedSize, frame, padding): `[0, 0]`, `[0, 0, 0]`,
    // `[0, 0, 0, 0]`; the VStack below them (`MC-A`, `MC-C`).
    expectFrame(b, id(0, 0), [0, 0, 400, 177], "form")
    let form = [0, 0, 0, 0, 0]
    func at(_ tail: Int...) -> GlobalElementID { controlID(form + tail) }
    expectFrame(b, at(0), [16, 16, 368, 16], "row a")
    expectFrame(b, at(0, 0), [16, 16, 35, 16], "label Name")
    expectFrame(b, at(0, 1), [59, 16, 325, 16], "TextField")
    expectFrame(b, at(1), [16, 40, 368, 24], "row b")
    expectFrame(b, at(1, 0), [16, 44, 70, 16], "Toggle(Enabled)")
    expectFrame(b, at(1, 2), [325, 40, 59, 24], "Button(Apply)")
    expectFrame(b, at(2), [16, 72, 368, 16], "row c")
    expectFrame(b, at(2, 0), [16, 72, 39, 16], "label Speed")
    expectFrame(b, at(2, 1), [63, 72, 321, 16], "Slider")
    expectFrame(b, at(3), [16, 96, 113, 24], "Picker.menu")
    expectFrame(b, at(4), [16, 128, 368, 1], "Divider")
    expectFrame(b, at(5), [16, 137, 368, 24], "row f")
    expectFrame(b, at(5, 0), [16, 137, 50, 24], "Stepper(Qty)")

    // The probe's relations, from the measured widths.
    let apply = try #require(b[at(1, 2)])
    #expect(apply.origin.x.value + apply.size.width.value == 384, "the trailing Button ends at 384")
    for (label, control) in [(at(0, 0), at(0, 1)), (at(2, 0), at(2, 1))] {
        let l = try #require(b[label]), c = try #require(b[control])
        #expect(c.size.width.value == 368 - l.size.width.value - 8, "the greedy control takes the rest: \(c)")
    }
    #expect(b[at(4)]?.size.width.value == 368, "the Divider spans")
}

/// **1.6** (`PE-B`, `PE-F` item 2; probe ST0). The configurator's status bar in
/// the SwiftUI vocabulary at 600×26: spec §1.3's MetalUI column (13 vs 14 tall:
/// divergence 86).
///
/// A second spelling writes the three middle labels as one
/// `ForEach(labels, id: \.self) { Text($0) }` — a single adopted expression of
/// three native nodes, which a port writes for a data-driven bar — and must lay
/// out identically (the `ForEach` takes one slot, its labels under it).
///
/// Red before: does not compile (`Text` in `HStack`, `.infinity`). Mutation
/// M1.6 (`LegacyContent`'s typed entry returns `nodes.reversed()`) reddens the
/// `ForEach` spelling — reversing matters only inside one multi-node adopted
/// expression, so the first spelling (single-node `Text`s) cannot see it.
@Test @MainActor func theConfiguratorsStatusBarLaysOutInTheSwiftUIVocabulary() throws {
    let report = LayoutDifferential.report(width: 600, height: 26) {
        HStack(spacing: px(16)) {
            HStack(spacing: px(6)) {
                Circle().frame(width: px(7), height: px(7))
                Text("USB Connected")
            }
            Text("Default · 5×14")
            Text("4 layers")
            Text("fw 1.2.3")
            Spacer()
            Text("keymap.json — unsaved changes")
        }
        .font(.system(size: 11))
        .padding(Edges(top: px(0), right: px(16), bottom: px(0), left: px(16)))
        .frame(maxWidth: .infinity, minHeight: px(26), maxHeight: px(26))
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let b = report.bounds
    // Two layers (frame, padding) over the transparent font scope (`EV-`).
    expectFrame(b, id(0, 0), [0, 0, 600, 26], "bar")
    let bar = [0, 0, 0, 0]
    func at(_ tail: Int...) -> GlobalElementID { controlID(bar + tail) }
    expectFrame(b, at(0), [16, 7, 96, 13], "dot group")
    expectFrame(b, at(0, 0), [16, 10, 7, 7], "dot")
    expectFrame(b, at(0, 1), [29, 7, 83, 13], "USB Connected")
    expectFrame(b, at(1), [128, 7, 74, 13], "Default · 5×14")
    expectFrame(b, at(2), [218, 7, 41, 13], "4 layers")
    expectFrame(b, at(3), [275, 7, 40, 13], "fw 1.2.3")
    expectFrame(b, at(5), [411, 7, 173, 13], "keymap.json — unsaved changes")

    let labels = ["Default · 5×14", "4 layers", "fw 1.2.3"]
    let data = LayoutDifferential.report(width: 600, height: 26) {
        HStack(spacing: px(16)) {
            HStack(spacing: px(6)) {
                Circle().frame(width: px(7), height: px(7))
                Text("USB Connected")
            }
            ForEach(labels, id: \.self) { Text($0) }
            Spacer()
            Text("keymap.json — unsaved changes")
        }
        .font(.system(size: 11))
        .padding(Edges(top: px(0), right: px(16), bottom: px(0), left: px(16)))
        .frame(maxWidth: .infinity, minHeight: px(26), maxHeight: px(26))
    }
    try #require(data.unlowerable.isEmpty, "\(data.unlowerable)")
    // Each element's scope is named by its id under the loop's one slot
    // (`DD-B`), and its `Text` is position 0 in that scope.
    func label(_ index: Int) -> GlobalElementID {
        GlobalElementID.child(of: GlobalElementID.child(of: at(1), at: index, name: ElementID(labels[index])),
                              at: 0, name: nil)
    }
    let named = data.bounds.keys.filter { $0.parent?.parent == at(1) }
    try #require(named.count == 3, "the ForEach's three labels under one slot: \(named)")
    expectFrame(data.bounds, label(0), [128, 7, 74, 13], "ForEach Default · 5×14")
    expectFrame(data.bounds, label(1), [218, 7, 41, 13], "ForEach 4 layers")
    expectFrame(data.bounds, label(2), [275, 7, 40, 13], "ForEach fw 1.2.3")
    expectFrame(data.bounds, at(3), [411, 7, 173, 13], "ForEach keymap.json — unsaved changes")
}

// MARK: - 1.7, 1.8 records and presentations

/// **1.7** (`PE-C` item 4, `LR-AQ`). A legacy item field on content in a
/// proposal stack is reported by name — nothing consumes it, and SwiftUI has no
/// flex fields: `HStack { TextField.flexGrow(1) }` →
/// `[textField.flexGrow.unconsumed]`, `VStack { Text.margin(4) }` →
/// `[text.margin.unconsumed]`.
///
/// Red before: does not compile. Mutation M1.7 (`LegacyContent` consumes its
/// nodes' records) → `[]`.
@Test @MainActor func aLegacyItemFieldInAProposalStackIsReportedByName() throws {
    let grow = LayoutDifferential.render(width: 300, height: 100) {
        HStack { TextField("", text: .constant("")).flexGrow(1) }
    }
    #expect(grow.unlowerableFields.map(\.description) == ["textField.flexGrow.unconsumed"],
            "\(grow.unlowerableFields.map(\.description))")
    let margin = LayoutDifferential.render(width: 300, height: 100) {
        VStack { Text("a").margin(px(4)) }
    }
    #expect(margin.unlowerableFields.map(\.description) == ["text.margin.unconsumed"],
            "\(margin.unlowerableFields.map(\.description))")
}

/// **1.8** (`PE-C` item 3, `LR-CK`). A `Deferred` presentation inside a proposal
/// stack takes no slot and no spacing — `b`'s minX is `a`'s maxX + 8 — and its
/// root is laid out against the window (its hitbox at (5, 5) 10×10).
///
/// Red before: does not compile. Mutation M1.8 (`droppingPresentations`
/// dropped) → `b` at `a`'s maxX + 16.
@Test @MainActor func aPresentationInsideAProposalStackTakesNoSlot() throws {
    let report = LayoutDifferential.report(width: 300, height: 100) {
        HStack {
            Text("a")
            Deferred {
                Box().background(.accent).onClick {}
                    .position(.absolute)
                    .inset(Edges(top: .length(.pixels(px(5))), right: .auto, bottom: .auto,
                                 left: .length(.pixels(px(5)))))
                    .cssWidth(px(10)).cssHeight(px(10))
            }
            Text("b")
        }
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let a = try #require(report.bounds[id(0, 0, 0)])
    let b = try #require(report.bounds[id(0, 0, 2)])
    #expect(b.origin.x.value == a.origin.x.value + a.size.width.value + 8,
            "the presentation takes no slot: a \(a), b \(b)")
    #expect(report.frame.hitboxes.contains { xywh($0.bounds) == [5, 5, 10, 10] },
            "the presentation root is laid out against the window: \(report.frame.hitboxes.map { xywh($0.bounds) })")
}

// MARK: - 1.10 text

/// **1.10** (`PE-G`). The legacy `Text` in a proposal stack lays out exactly as
/// `ProposalText`: a wrapping pair at 120×100, and a `.firstTextBaseline` row
/// with a 20-pt first child, element by element.
///
/// Red before: does not compile. Mutation M1.10 (`Text.requestLayout` measures
/// with `wrappingAt: nil`) reddens the wrapping arm.
@Test @MainActor func textInAProposalStackLaysOutAsProposalText() throws {
    let legacy = LayoutDifferential.report(width: 120, height: 100) {
        HStack { Text(longLabel); Text("b") }
    }
    let proposal = LayoutDifferential.report(width: 120, height: 100) {
        HStack { ProposalText(longLabel); ProposalText("b") }
    }
    try #require(legacy.unlowerable.isEmpty && proposal.unlowerable.isEmpty)
    for path in [[0, 0], [0, 0, 0], [0, 0, 1]] {
        let l = try #require(legacy.bounds[controlID(path)], "legacy \(path)")
        let p = try #require(proposal.bounds[controlID(path)], "proposal \(path)")
        #expect(l == p, "wrapping \(path): \(l) vs \(p)")
    }
    let wrapped = try #require(legacy.bounds[id(0, 0, 0)])
    try #require(wrapped.size.height.value > 16, "set up: the long label wraps: \(wrapped)")

    let legacyBaseline = LayoutDifferential.report(width: 300, height: 100) {
        HStack(alignment: .firstTextBaseline) { Text("A").font(.system(size: 20)); Text("b") }
    }
    let proposalBaseline = LayoutDifferential.report(width: 300, height: 100) {
        HStack(alignment: .firstTextBaseline) { ProposalText("A").font(.system(size: 20)); ProposalText("b") }
    }
    for path in [[0, 0], [0, 0, 0], [0, 0, 1]] {
        let l = try #require(legacyBaseline.bounds[controlID(path)], "legacy \(path)")
        let p = try #require(proposalBaseline.bounds[controlID(path)], "proposal \(path)")
        #expect(l == p, "baseline \(path): \(l) vs \(p)")
    }
    let big = try #require(legacyBaseline.bounds[id(0, 0, 0)])
    let small = try #require(legacyBaseline.bounds[id(0, 0, 1)])
    #expect(small.origin.y.value > big.origin.y.value, "set up: the baselines align, not the tops")
}

// MARK: - 1.11–1.15 the control's own behaviour, in both vocabularies

/// **1.11** (`PE-C` item 5, `PE-I`). In an `HStack` — and in a `Row`, for
/// comparison — the Button has exactly one hitbox at its frame; a click runs
/// the action once; Tab focuses it; Space activates; `.disabled(true)` on the
/// stack and on the Button gate the click.
///
/// Red before: does not compile. Mutation M1.11 (`PE-S`: `LegacyContent`'s
/// prepaint runs its content's prepaint twice, a discarded first call) → two
/// hitboxes at the Button's frame.
@Test @MainActor func aButtonInAProposalStackHasOneHitboxAndActsAsInARow() throws {
    func check<Root: Element>(_ name: String, _ make: @escaping @MainActor (ControlModel) -> Root) throws {
        let model = ControlModel()
        let (window, platform) = try controlWindow { make(model) }
        let buttonID = id(0, 0)
        let button = try controlBounds(window.lastFrameBounds(), buttonID)
        let atButton = window.lastHitboxes.filter { $0.bounds == button }
        #expect(atButton.count == 1, "\(name): one hitbox at the Button's frame, got \(atButton.count)")
        controlClick(platform, at: controlCentre(button))
        #expect(model.count == 1, "\(name): a click runs the action once")
        #expect(window.focusedElement == nil, "\(name): a click does not focus (divergence 94)")
        platform.simulateInput(controlKey("\t"))
        window.drawFrameIfNeeded()
        #expect(window.focusedElement == buttonID, "\(name): Tab focuses the Button")
        platform.simulateInput(controlKey(" "))
        #expect(model.count == 2, "\(name): Space activates")
        withExtendedLifetime(window) {}
    }
    try check("HStack") { model in HStack { Button("Go") { model.count += 1 } } }
    try check("Row") { model in Row { Button("Go") { model.count += 1 } } }

    for (name, onStack) in [("on the stack", true), ("on the Button", false)] {
        let model = ControlModel()
        let (window, platform) = try controlWindow {
            VStack {
                if onStack {
                    HStack { Button("Go") { model.count += 1 } }.disabled(true)
                } else {
                    HStack { Button("Go") { model.count += 1 }.disabled(true) }
                }
            }
        }
        // The `if`/`else` takes two slots under the root (`ID-D`); each branch
        // numbers its HStack 0 under its own slot, and `.disabled` is a
        // transparent scope (`EV-`).
        let button = try controlBounds(window.lastFrameBounds(), onStack ? id(0, 0, 0, 0) : id(0, 1, 0, 0))
        controlClick(platform, at: controlCentre(button))
        #expect(model.count == 0, "\(name): .disabled(true) gates the click")
        withExtendedLifetime(window) {}
    }
}

/// **1.12** (`PE-I`, `OM-AI`'s paint half). The scene holds the Button's chrome
/// rect at its frame and its label's glyphs inside it, in an `HStack` as in a
/// `Row`.
///
/// Red before: does not compile. Mutation M1.12 (`LegacyContent.paintGroup`
/// skips its content) → no chrome, no glyphs.
@Test @MainActor func aControlInAProposalStackPaints() throws {
    let stacked: Frame = LayoutDifferential.render(width: 400, height: 100) { HStack { Button("Go") {} } }
    let rowed: Frame = LayoutDifferential.render(width: 400, height: 100) { Row { Button("Go") {} } }
    for (name, frame) in [("HStack", stacked), ("Row", rowed)] {
        let button = try #require(frame.elementBounds[id(0, 0)], "\(name): the Button's bounds")
        let chrome: [Float] = xywh(button)
        let rects = frame.scene.rects.filter { (rect: MUIRect) -> Bool in
            let b: [Float] = [rect.bounds.origin.x, rect.bounds.origin.y, rect.bounds.size.width,
                              rect.bounds.size.height]
            return zip(b, chrome).allSatisfy { near($0, $1) }
        }
        #expect(!rects.isEmpty, "\(name): the chrome rect at \(xywh(button))")
        let left: Float = button.origin.x.value
        let right: Float = left + button.size.width.value
        let glyphs = frame.scene.glyphs.filter { (glyph: MUIGlyph) -> Bool in
            glyph.bounds.origin.x >= left && glyph.bounds.origin.x < right
        }
        #expect(glyphs.count >= 2, "\(name): the label's two glyphs inside the Button")
    }
}

/// One accessibility node as `(role, label, value)`, for a literal list.
private struct AXRecord: Hashable, CustomStringConvertible {
    var role: String
    var label: String?
    var value: String?
    var description: String { "\(role) \(label ?? "-") \(value ?? "-")" }
}

@MainActor
private func axRecords(_ frame: Frame) -> [AXRecord] {
    let tree = AccessibilityTreeBuilder.build(emissions: frame.axEmissions, focused: frame.focusedElement,
                                              hitboxes: frame.hitboxes, focusRegistry: frame.focusRegistry)
    return tree.nodes.values.map { AXRecord(role: "\($0.role)", label: $0.label, value: $0.value) }
        .sorted { $0.description < $1.description }
}

/// **1.13** (`PE-I`, `PE-S`). With a client active, the controls of
/// `HStack { Button; Toggle; Slider; TextField; Picker }` record the literal
/// roles, labels and values written here, and the same records as the `Row`
/// spelling.
///
/// Red before: does not compile. Mutations: M1.13 (`Toggle`'s role →
/// `.button`; the literal list can fail where the cross-vocabulary equality
/// cannot) and M1.4a (a fresh cursor: colliding ids lose records). The spec's
/// claim that M1.11 (prepaint run twice) reddens this test too was measured
/// false — the tree builder keys records by id, so a doubled emission collapses
/// (`PE-X`).
@Test @MainActor func accessibilityRecordsOfControlsAgreeAcrossVocabularies() throws {
    let proposal = LayoutDifferential.render(width: 600, height: 100) {
        HStack {
            Button("Go") {}
            Toggle("Wi-Fi", isOn: .constant(true))
            Slider(value: .constant(0.5))
            TextField("Name", text: .constant("Hello"))
            Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }
        }
    }
    let legacy = LayoutDifferential.render(width: 600, height: 100) {
        Row {
            Button("Go") {}
            Toggle("Wi-Fi", isOn: .constant(true))
            Slider(value: .constant(0.5))
            TextField("Name", text: .constant("Hello"))
            Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }
        }
    }
    try #require(proposal.unlowerableFields.isEmpty && legacy.unlowerableFields.isEmpty)
    let records = axRecords(proposal)
    let expected: [AXRecord] = [
        AXRecord(role: "button", label: "Go", value: nil),
        AXRecord(role: "checkBox", label: "Wi-Fi", value: "1"),
        AXRecord(role: "radioButton", label: "Alpha", value: "1"),
        AXRecord(role: "radioButton", label: "Beta", value: "0"),
        AXRecord(role: "radioGroup", label: "Mode", value: nil),
        AXRecord(role: "slider", label: nil, value: "0.5"),
        AXRecord(role: "textField", label: "Name", value: "Hello"),
    ].sorted { $0.description < $1.description }
    #expect(records == expected, "the literal records: \(records)")
    #expect(records == axRecords(legacy), "the Row spelling records the same: \(axRecords(legacy))")
}

/// **1.14** (`PE-I`, `PE-S`). Tab visits the controls of a `VStack` in tree
/// order — the literal id list written here — and the `Column` spelling's
/// order is the same list.
///
/// Red before: does not compile. Mutation M1.14 (`Stepper`'s `isFocusable =
/// false`) reddens the literal list.
@Test @MainActor func tabVisitsControlsInAProposalStackInTreeOrder() throws {
    func order<Root: Element>(_ make: @escaping @MainActor () -> Root) throws -> [GlobalElementID] {
        let (window, _) = try controlWindow(make)
        defer { withExtendedLifetime(window) {} }
        return window.lastFocusRegistry.tabOrder
    }
    let proposal = try order {
        VStack {
            TextField("Name", text: .constant(""))
            Button("Go") {}
            Toggle("On", isOn: .constant(true))
            Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }
            Slider(value: .constant(0.5))
            Stepper("Qty", value: .constant(1), in: 0...3)
        }
    }
    let legacy = try order {
        Column {
            TextField("Name", text: .constant(""))
            Button("Go") {}
            Toggle("On", isOn: .constant(true))
            Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }
            Slider(value: .constant(0.5))
            Stepper("Qty", value: .constant(1), in: 0...3)
        }
    }
    let expected = [id(0, 0), id(0, 1), id(0, 2), id(0, 3), id(0, 4), id(0, 5)]
    #expect(proposal == expected, "the literal Tab order: \(proposal)")
    #expect(proposal == legacy, "the Column spelling's order: \(legacy)")
}

@MainActor private final class Log {
    var entries: [String] = []
}

/// **1.15** (`PE-I`). On a Button in an `HStack`: `.keyboardShortcut("k")` fires
/// with focus on another control; `.help("tip")` is the accessibility hint;
/// `.onHover` reports enter and exit from injected moves.
///
/// Red before: does not compile. Mutation M1.15 (`Window`'s shortcut stage
/// skips a `ShortcutTarget`) reddens the shortcut arm.
@Test @MainActor func aShortcutHelpAndHoverWorkOnAButtonInAProposalStack() throws {
    let log = Log()
    let (window, platform) = try controlWindow {
        HStack {
            Button("K") { log.entries.append("k") }
                .keyboardShortcut("k")
                .help("tip")
                .onHover { log.entries.append("hover \($0)") }
            Button("Other") { log.entries.append("other") }
        }
    }
    window.focus(id(0, 1))
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id(0, 1), "set up: focus is on the other Button")
    #expect(platform.simulateInput(controlKey("k", .command)), "⌘K is claimed")
    #expect(log.entries == ["k"], "the shortcut fires its Button with focus elsewhere")

    let button = try controlBounds(window.lastFrameBounds(), id(0, 0))
    platform.simulateInput(.mouseMoved(MouseEvent(position: controlCentre(button))))
    platform.simulateInput(.mouseMoved(MouseEvent(position: Point(x: px(399), y: px(399)))))
    #expect(log.entries == ["k", "hover true", "hover false"], "onHover: \(log.entries)")

    let tree = try controlTree(window, platform)
    let node = try #require(tree.nodes.values.first { $0.label == "K" }, "the Button's node")
    #expect(node.hint == "tip", ".help is the accessibility hint: \(String(describing: node.hint))")
    withExtendedLifetime(window) {}
}

// MARK: - 1.16–1.19 animation, drag, list, popover

@MainActor private final class Width {
    var value: Float = 100
}

/// **1.16** (`PE-I`). A legacy `.frame(width:)` on a Button inside an `HStack`
/// animates: changed 100 → 200 under `withAnimation(.linear(duration: 1))`, the
/// width at 0.5 s is midway, 150, and 200 settled.
///
/// Red before: does not compile. Mutation M1.16 (the frame layer's
/// `animated(_:_:for:pass:)` call removed) → it snaps to 200.
@Test @MainActor func aLegacyFrameAnimatesInsideAProposalStack() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let width = Width()
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        HStack { Button("Go") {}.frame(width: px(width.value)) }
    }
    window.recordsElementBounds = true
    let button = id(0, 0)
    func current() -> Float? { window.lastElementBounds[button]?.size.width.value }
    platform.simulateTick(timestamp: 100)
    try #require(current() == 100, "set up: 100 wide, got \(String(describing: current()))")
    withAnimation(.linear(duration: 1)) {
        width.value = 200
        window.setNeedsRedraw()
    }
    platform.simulateTick(timestamp: 100)
    platform.simulateTick(timestamp: 100.5)
    #expect(current().map { near($0, 150) } == true, "midway at 0.5 s: \(String(describing: current()))")
    platform.simulateTick(timestamp: 101.5)
    #expect(current() == 200, "settled: \(String(describing: current()))")
    withExtendedLifetime(window) {}
}

/// **1.17** (`PE-I`, `DN-X`). `Text("drag").draggable("x")` in an `HStack`:
/// after a press and a move a drag session exists and its preview capture is
/// non-empty.
///
/// Red before: does not compile. Mutation M1.17 (`Text.paint` bypasses
/// `paintDecoration`) → an empty capture.
@Test @MainActor func aDragFromAControlInAProposalStackCarriesAPreview() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 400, startsDisplayLink: true) {
        HStack { Text("drag").draggable("x") }
    }
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    let text = try controlBounds(window.lastFrameBounds(), id(0, 0))
    let p = controlCentre(text)
    platform.simulateInput(.mouseDown(MouseEvent(position: p)))
    platform.simulateInput(.mouseDragged(MouseEvent(position: Point(x: px(p.x.value + 1), y: p.y))))
    platform.simulateInput(.mouseDragged(MouseEvent(position: Point(x: px(p.x.value + 40), y: p.y))))
    window.drawFrameIfNeeded()
    let session = try #require(window.dragSession, "a drag session began")
    #expect(!session.snapshot.isEmpty, "the preview capture is non-empty (DN-X)")
    platform.simulateInput(.mouseUp(MouseEvent(position: Point(x: px(p.x.value + 40), y: p.y))))
    withExtendedLifetime(window) {}
}

@MainActor private final class ListModel {
    var selected: Int?
    var binding: Binding<Int?> { Binding(get: { self.selected }, set: { self.selected = $0 }) }
}

/// **1.18** (`PE-I`, `DD-F`, `DD-Z`). A selectable `List` in a `VStack` in a
/// 100-tall `ProposalScrollView`, over two frames: its window is bounded
/// (row 0 realised, row 30 not — `try #require`d), and a click on row 1 selects
/// it and focuses the list.
///
/// **The windowing needs `PE-V`**: until this lane a `ProposalScrollView`
/// published no `ScrollContext` (`LR-BF`), so a `List` in it realised all 40
/// rows (measured on this branch with `PE-B` alone: rows 0…39 recorded).
///
/// Red before: does not compile; with the builder alone, row 30 realised.
/// Mutations: M1.18 (`List.visibleRange` returns `0..<count`) and M1.18b
/// (`ProposalScrollView` publishes no context) → row 30 realised.
@Test @MainActor func aSelectableListInAProposalScrollViewWindowsAndSelects() throws {
    let model = ListModel()
    let items = (0..<40).map(Item.init)
    let (window, platform) = try controlWindow {
        VStack {
            ProposalScrollView {
                VStack {
                    List(items, selection: model.binding, rowHeight: px(20)) { item in Text("Row \(item.id)") }
                }
            }
            .frame(width: px(200), height: px(100))
        }
    }
    controlRedraw(window)
    func row(_ index: Int) -> (GlobalElementID, Bounds<Pixels>)? {
        window.lastElementBounds.first { key, _ in key.component == PathComponent.named(ElementID("\(index)")) }
            .map { ($0.key, $0.value) }
    }
    let (row1, row1Bounds) = try #require(row(1), "row 1 is realised")
    try #require(row(0) != nil, "row 0 is realised")
    try #require(row(30) == nil, "the window is bounded: row 30 is not realised")
    let list = try #require(row1.parent, "a row sits under its list")
    controlClick(platform, at: controlCentre(row1Bounds))
    window.drawFrameIfNeeded()
    #expect(model.selected == 1, "a click selects the row")
    #expect(window.focusedElement == list, "and focuses the list: \(String(describing: window.focusedElement))")
    withExtendedLifetime(window) {}
}

/// **1.19** (`PE-I`, `MN-`). A presented `.popover` on a Button in an `HStack`
/// lays out a presentation root, and the Button's frame equals its frame
/// without the popover.
///
/// Red before: does not compile. Mutation M1.19 (the popover's presentation
/// registration skipped) → no open popover.
@Test @MainActor func aPopoverOnAButtonInAProposalStackPresents() throws {
    let (plain, _) = try controlWindow {
        HStack { Button("Go") {}; Text("b") }
    }
    let (window, _) = try controlWindow {
        HStack {
            Button("Go") {}.popover(isPresented: .constant(true)) {
                Box().frame(width: px(100), height: px(50))
            }
            Text("b")
        }
    }
    for _ in 0..<4 where window.needsRedraw { window.drawFrameIfNeeded() }
    #expect(!window.lastOpenPopovers.isEmpty, "the popover is presented")
    #expect(window.lastElementBounds[id(0, 0)] == plain.lastElementBounds[id(0, 0)],
            "the Button's frame is unchanged by its popover")
    #expect(window.lastElementBounds[id(0, 1)] == plain.lastElementBounds[id(0, 1)],
            "the next sibling's frame is unchanged")
    withExtendedLifetime((window, plain)) {}
}

// MARK: - 1.20, 1.22 the proposal-only modifiers and a grid form

/// **1.20** (`PE-F` item 1). The proposal-only modifiers reach legacy content:
/// `HStack { Text(long).layoutPriority(1); TextField }` at 200 serves the Text
/// first, its whole width; `VStack { Text(long).fixedSize() }` at 50 keeps one
/// line; `Text("a").gridCellColumns(2)` spans both columns of the next row.
///
/// Red before: does not compile. Mutation M1.20 (the `ElementGroup.layoutPriority`
/// spelling returns `LegacyContent(self)` without the layer) → the Text wraps.
@Test @MainActor func theProposalOnlyModifiersReachLegacyContent() throws {
    let priority = LayoutDifferential.report(width: 200, height: 100) {
        HStack {
            Text(longLabel).layoutPriority(1)
            TextField("", text: .constant(""))
        }
    }
    try #require(priority.unlowerable.isEmpty, "\(priority.unlowerable)")
    // The layer is one id level: the Text under `[0, 0, 0]` (`MC-C`).
    let text = try #require(priority.bounds[id(0, 0, 0, 0)], "the prioritised Text")
    let field = try #require(priority.bounds[id(0, 0, 1)], "the TextField")
    #expect(text.size.height.value == 16 && (120...121).contains(text.size.width.value),
            "the Text takes its whole width, one line: \(text)")
    #expect(field.size.width.value == 200 - text.size.width.value - 8, "the field takes the rest: \(field)")

    let fixed = LayoutDifferential.report(width: 50, height: 100) {
        VStack { Text(longLabel).fixedSize() }
    }
    try #require(fixed.unlowerable.isEmpty, "\(fixed.unlowerable)")
    let one = try #require(fixed.bounds[id(0, 0, 0, 0)], "the fixed Text")
    #expect(one.size.height.value == 16 && one.size.width.value > 50, "one line, wider than 50: \(one)")

    let grid = LayoutDifferential.report(width: 300, height: 100) {
        Grid {
            GridRow { Text("a").gridCellColumns(2) }
            GridRow { Text("b"); Text("c") }
        }
    }
    try #require(grid.unlowerable.isEmpty, "\(grid.unlowerable)")
    let a = try #require(grid.bounds[id(0, 0, 0, 0)], "the spanning cell")
    let b = try #require(grid.bounds[id(0, 0, 1, 0)])
    let c = try #require(grid.bounds[id(0, 0, 1, 1)])
    let spanMid = (b.origin.x.value + c.origin.x.value + c.size.width.value) / 2
    #expect(near(a.origin.x.value + a.size.width.value / 2, spanMid),
            "a is centred over both columns: a \(a), b \(b), c \(c)")
}

/// **1.22** (`PE-B`, `PE-D`). A two-column grid form at 300: column 0 is the
/// wider label's, column 1 takes 300 − column 0 − 8 for both the `TextField`
/// and the `Slider` (hand-derived from the measured label width).
///
/// Red before: does not compile. Mutations M1.4a and M1.4b (the adapter's
/// cursor or level) redden it. The spec's M1.22 (`Slider`'s `PE-D` reverted)
/// was measured NOT to: the grid offers its greedy column the rest whatever the
/// slider answers at ∞ (`PE-X` correction 2).
@Test @MainActor func aGridFormGivesItsFieldColumnTheRest() throws {
    let report = LayoutDifferential.report(width: 300, height: 100) {
        Grid {
            GridRow {
                Text("Name")
                TextField("", text: .constant(""))
            }
            GridRow {
                Text("Description")
                Slider(value: .constant(0.5))
            }
        }
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let name = try #require(report.bounds[id(0, 0, 0, 0)])
    let description = try #require(report.bounds[id(0, 0, 1, 0)])
    let field = try #require(report.bounds[id(0, 0, 0, 1)])
    let slider = try #require(report.bounds[id(0, 0, 1, 1)])
    let column0 = max(name.size.width.value, description.size.width.value)
    try #require(column0 == description.size.width.value, "set up: Description is the wider label")
    for (label, cell) in [("TextField", field), ("Slider", slider)] {
        #expect(cell.size.width.value == 300 - column0 - 8, "\(label) takes the rest: \(cell)")
        #expect(cell.origin.x.value == column0 + 8, "\(label) starts after column 0: \(cell)")
    }
}
