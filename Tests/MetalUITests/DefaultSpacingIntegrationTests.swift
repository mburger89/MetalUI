import Testing
@testable import MetalUI
import MetalUICore
import MetalUILayout
import MetalUITextSystem

// R4-2 PR B (`DS-E`..`DS-H`, record 203): the default spacing at a text edge through the element API, with the
// CoreText system the frame defaults to on macOS. **The literals are SwiftUI's, from
// `docs/probes/swiftui-default-spacing-run.txt`** (macOS 27.2): at the default 13 pt font rect|text 4.742,
// text|rect 8.151, text|text 0; at `.system(size: 26)` 9.484 and 16.302. CoreText figures are not portable, so
// this file is macOS only; the portable arms are `MetalUILayoutTests/DefaultSpacingTests.swift`. Every gap is read
// unrounded through `measureNativeLayout` (a placed rect is rounded: 8.151 would read the old 8).

private func px(_ value: Float) -> Pixels { Pixels(value) }

/// A fixed 20×20 block: the "rect" of the probe (a fixed frame is a standard edge).
@MainActor private func block() -> some ProposalElementGroup {
    Color(.accent).frame(width: px(20), height: px(20))
}

@MainActor private func height<E: ProposalElement>(_ element: E, width: Double? = nil) -> Double {
    var copy = element
    let frame = Frame(contentSize: Size(width: px(400), height: px(400)), scaleFactor: 1)
    var pass = LayoutPass(frame: frame)
    let (node, _) = copy.requestProposalLayout(GlobalElementID.child(of: nil, at: 0, name: nil), pass: &pass)
    return frame.tree.measureNativeLayout(root: node.layoutNodeID,
                                          proposal: ProposedSize(width: width, height: nil)).size.height
}

/// The default gap between `upper` and `lower` in a `VStack`: its height minus the two children's own.
@MainActor private func gap<U: ElementGroup, L: ElementGroup>(_ upper: U, _ lower: L) -> Double {
    height(VStack { upper; lower }) - height(VStack { upper }) - height(VStack { lower })
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.002 }

// MARK: - the leaves

/// **A plain `Text` and a plain `ProposalText` take the font's text edges** (rows 51 and 65 retired in part): rect
/// above text 4.742, text above rect 8.151, text above text 0, rect above rect 8 (the control). Two spellings, one
/// site each (`OM-AI`). Mutations: **M13** `Text.swift`'s plain site not marked (the `Text` arm reads 8, 8, 8);
/// **M14** `ProposalText.swift`'s plain site not marked (the `ProposalText` arm).
@MainActor @Test func aPlainTextLeafTakesItsTextEdges() {
    #expect(gap(block(), block()) == 8, "rect|rect keeps 8")
    #expect(near(gap(block(), ProposalText("Alpha")), 4.742) && near(gap(ProposalText("Alpha"), block()), 8.151),
            "ProposalText beside a rect")
    #expect(gap(ProposalText("Alpha"), ProposalText("Bravo")) == 0, "ProposalText over ProposalText")
    #expect(near(gap(block(), Text("Alpha")), 4.742) && near(gap(Text("Alpha"), block()), 8.151), "Text beside a rect")
    #expect(gap(Text("Alpha"), Text("Bravo")) == 0, "Text over Text")
    #expect(gap(Text("Alpha"), ProposalText("Bravo")) == 0, "Text over ProposalText")
}

/// **A styled (rich) text takes them too** (`RT-F` item 3: any set run or view-level field makes a text styled):
/// `.underline()` at 13 pt reads the plain figures, and a text whose font is 26 pt reads the 26's (the largest
/// run's font). Mutation **M15**: the rich site (`Text.swift` and `ProposalText.swift`) not marked.
@MainActor @Test func aRichTextLeafTakesItsTextEdges() {
    #expect(near(gap(block(), Text("Alpha").underline()), 4.742), "underlined Text below a rect")
    #expect(near(gap(Text("Alpha").underline(), block()), 8.151), "underlined Text above a rect")
    #expect(near(gap(block(), ProposalText("Alpha").underline()), 4.742), "underlined ProposalText below a rect")
    #expect(near(gap(ProposalText("Alpha").underline(), block()), 8.151), "underlined ProposalText above a rect")
    let big = Text("Alpha").font(.system(size: 26)).underline()
    #expect(near(gap(block(), big), 9.484) && near(gap(big, block()), 16.302), "underlined 26 pt Text")
}

/// **The gap follows the font** (DS1 at 26 pt, DS10): `.font(.system(size: 26))` on the text reads 9.484 and
/// 16.302 where 13 pt reads 4.742 and 8.151; a font set on the STACK is inherited by its texts and changes
/// nothing else (rect|rect 8); a text at 26 over one at 13 is the lower's leading, 0.
/// Mutation **M1** at the integration level: a gap that ignores the metrics reads one pair of figures for both.
@MainActor @Test func aFontChangeMovesTheGap() {
    let big = ProposalText("Alpha").font(.system(size: 26))
    #expect(near(gap(block(), big), 9.484) && near(gap(big, block()), 16.302), "26 pt")
    #expect(gap(big, ProposalText("Bravo")) == 0 && gap(ProposalText("Bravo"), big) == 0, "26 beside 13")
    let stack = VStack { block(); ProposalText("Alpha") }.font(.system(size: 26))
    let inherited = height(VStack { stack })
    let own = height(VStack { block(); big })
    #expect(near(inherited, own), "a stack's font reaches its texts: \(inherited) vs \(own)")
    let rects = VStack { block(); block() }.font(.system(size: 26))
    #expect(height(VStack { rects }) == 48, "and changes nothing else")
}

/// An empty text has no vertical edge (DS6 `empty`), and 8 horizontally. Mutation **M24**: an empty text marked
/// as text, or not marked (its gap above a rect reads 4.742 or 8).
@MainActor @Test func anEmptyTextHasNoVerticalEdge() {
    #expect(gap(block(), ProposalText("")) == 0 && gap(ProposalText(""), block()) == 0, "empty beside a rect")
    #expect(gap(ProposalText(""), ProposalText("x")) == 0, "empty beside a text")
    let row = height(HStack { block(); ProposalText("") }.fixedSize())
    #expect(row == 20, "an empty text keeps a row's height: \(row)")
}

/// **Rows of icon and label keep their gaps** (`DS-G2`; probe `DS9b`): `VStack { HStack { block; Text }; Text }` is
/// 4.742 between the row and the text below it (the three-kind union read 0 here, and the old code 8), a row above
/// a row 8.151, a text above a row 8.151. Through the element API, with an image in place of the block too.
/// Mutation **MX2**: `mixed` collapsed to `text`.
@MainActor @Test func aRowOfIconAndLabelKeepsItsGaps() {
    func row() -> some ElementGroup { HStack { block(); ProposalText("Alpha") } }
    #expect(near(gap(row(), ProposalText("Bravo")), 4.742), "row over text")
    #expect(near(gap(ProposalText("Bravo"), row()), 8.151), "text over row")
    #expect(near(gap(row(), row()), 8.151), "row over row")
    #expect(near(gap(block(), row()), 4.742) && near(gap(row(), block()), 8.151), "beside a block")
}

// MARK: - the controls (DS7, DS-H)

private struct ControlArm {
    let name: String
    let standard: Bool
    let make: @MainActor () -> AnyElement
}

@MainActor private func controlArms() -> [ControlArm] {
    func arm(_ name: String, standard: Bool = true, _ make: @escaping @MainActor () -> some Element) -> ControlArm {
        ControlArm(name: name, standard: standard, make: { AnyElement(make()) })
    }
    return [
        arm("Button automatic") { Button("Go") {} },
        arm("Button bordered") { Button("Go") {}.buttonStyle(.bordered) },
        arm("Button borderedProminent") { Button("Go") {}.buttonStyle(.borderedProminent) },
        arm("Button glass") { Button("Go") {}.buttonStyle(.glass) },
        arm("Button glassProminent") { Button("Go") {}.buttonStyle(.glassProminent) },
        arm("Toggle automatic") { Toggle("Go", isOn: .constant(true)) },
        arm("Toggle checkbox") { Toggle("Go", isOn: .constant(true)).toggleStyle(.checkbox) },
        arm("Toggle switch") { Toggle("Go", isOn: .constant(true)).toggleStyle(.switch) },
        arm("Toggle button") { Toggle("Go", isOn: .constant(true)).toggleStyle(.button) },
        arm("Stepper") { Stepper("Go", value: .constant(1), in: 0...3) },
        arm("Picker menu") { Picker("Go", selection: .constant(0)) { Text("A").tag(0) }.pickerStyle(.menu) },
        arm("Picker segmented") { Picker("Go", selection: .constant(0)) { Text("A").tag(0); Text("B").tag(1) }.pickerStyle(.segmented) },
        arm("Picker radioGroup") { Picker("Go", selection: .constant(0)) { Text("A").tag(0) }.pickerStyle(.radioGroup) },
        arm("ColorPicker") { ColorPicker("Go", selection: .constant(.red)) },
        arm("ProgressView titled") { ProgressView("Go", value: 0.5 as Double?) },
        arm("Slider") { Slider(value: .constant(0.5)) },
        arm("TextField") { TextField("Go", text: .constant("")) },
        // The text edges (DS7 `.plain` Button): the label alone.
        arm("Button plain", standard: false) { Button("Go") {}.buttonStyle(.plain) },
        arm("Button borderless", standard: false) { Button("Go") {}.buttonStyle(.borderless) },
        arm("Button link", standard: false) { Button("Go") {}.buttonStyle(.link) },
    ]
}

/// **Every control keeps a standard edge beside a text** (`DS-H`; probe `DS7`: default `Button`, `Toggle` in
/// every look, `Stepper`, `Picker`, `ColorPicker`, `ProgressView`, `Slider`, `TextField` are all standard, so a text
/// above one is 8.151 and a text below one 4.742), **and the label-alone buttons take text edges** (`.plain`,
/// `.borderless` and `.link` over a text: 0, below a rect: 4.742). Twenty arms, `try #require` on the count.
/// Separating control: a plain `Text` beside the control reads the text edge, so a control that registers its
/// label as a marked leaf (the flag never set) reads 0 and 4.742 where it must read 8.151 and 4.742's mirror.
///
/// Mutation **M16**: `markControlSpacing` not called by `Button`, `Toggle`, `Stepper`, `Picker`, `ColorPicker` or
/// `ProgressView` (one at a time; the arms of that control, and only those).
@MainActor @Test func everyControlKeepsAStandardEdgeBesideText() throws {
    let arms = controlArms()
    try #require(arms.count == 20, "the guard enumerates twenty controls and looks: \(arms.count)")
    for arm in arms {
        let control = arm.make()
        let above = gap(ProposalText("Alpha"), control)   // text above the control
        let below = gap(control, ProposalText("Alpha"))   // the control above a text
        if arm.standard {
            #expect(near(above, 8.151), "\(arm.name): text above it \(above) (a standard edge: 8.151)")
            #expect(near(below, 4.742), "\(arm.name): it above a text \(below) (a standard edge: 4.742)")
            #expect(near(gap(block(), arm.make()), 8) && near(gap(arm.make(), block()), 8), "\(arm.name): beside a rect")
        } else {
            #expect(above == 0, "\(arm.name): text above its text label \(above) (text over text: 0)")
            #expect(near(gap(block(), arm.make()), 4.742), "\(arm.name): below a rect (4.742)")
        }
    }
}

/// Divergence 213 (row, narrowed from the Toggle edge): SwiftUI's checkbox `Toggle` is 6 beside a rect and a
/// toggle (DS7), MetalUI's is the standard 8. Pinned wrong on purpose; `Image(systemName:)` is not offered, so
/// there is no symbol edge to pin. Mutation: a `Toggle` edge of 6 (`markControlSpacing` replaced by a 6 mark).
@MainActor @Test func aToggleBesideAToggleKeepsEight() {
    #expect(gap(Toggle("A", isOn: .constant(true)), Toggle("B", isOn: .constant(false))) == 8, "SwiftUI reads 6")
    #expect(gap(block(), Toggle("A", isOn: .constant(true))) == 8, "SwiftUI reads 6 beside a rect")
}

// MARK: - the lazy containers (row 51 narrowed)

/// **Row 51, narrowed to the lazy containers** (rulings `DS-I`; probe `DS13`: SwiftUI's `LazyVStack` follows the
/// stack rule, text|text 0, rect|text 4.742): MetalUI's `LazyVStack` and `LazyVGrid` keep one constant 8 between
/// children (`LazyStack.swift:167`, `LazyGrid.swift`), so `{text; text}` is 2 lines + 8 where `VStack`'s is
/// 2 lines. Pinned wrong on purpose. Mutation: the lazy stack's gap read from `defaultGap` (lazy planner
/// estimates move; the pin reads 32).
@MainActor @Test func aLazyStackKeepsEightBesideText() throws {
    final class Log { var bounds: [String: Bounds<Pixels>] = [:] }
    let log = Log()
    struct Mark: ProposalElement {
        let name: String
        let log: Log
        func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
            (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }, ())
        }
        func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
            log.bounds[name] = bounds
        }
        func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
                   pass: inout PaintPass) {}
    }
    var root = LazyVStack(alignment: .leading) {
        ProposalText("Alpha")
        ProposalText("Bravo")
        Mark(name: "m", log: log)
    }.frame(width: px(300), height: px(300), alignment: .topLeading)
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)), scaleFactor: 1)
    frame.render(&root)
    let y = try #require(log.bounds["m"]).origin.y.value
    #expect(y == 16 + 8 + 16 + 8, "the lazy stack keeps 8 between its children (a VStack reads 32): \(y)")
}

// MARK: - the form (FM0)

/// **The controls form reads FM0's own 182.04** (probe `swiftui-controls-in-stacks.swift` FM0; `DS9` "FM0 {Text;
/// Slider}|{Toggle; Spacer; Button}" 8.151). Unrounded, from the row gaps the probe's form origins give (8.151, 4.742,
/// 8.151, 8, 8) and the row heights (24, 24, 16, 24, 1, 24) under 16 padding: 16 + 24 + 8.151 + 24 + 4.742 + 16 +
/// 8.151 + 24 + 8 + 1 + 8 + 24 + 16 = 182.044. The prediction before the change was `185 - 40 + 37.04`. Mutation **M25**:
/// the control mark dropped from `Toggle`/`Button` (the row gap reads text|text 0 where FM0's is 8.151).
@MainActor @Test func theFormMatchesFM0() {
    let form = VStack(alignment: .leading) {
        HStack { Text("Name"); TextField("Name", text: .constant("")) }
        HStack { Toggle("Enabled", isOn: .constant(true)); Spacer(); Button("Apply") {} }
        HStack { Text("Speed"); Slider(value: .constant(0.5)) }
        Picker("Mode", selection: .constant(0)) { Text("Alpha").tag(0); Text("Beta").tag(1) }.pickerStyle(.menu)
        Divider()
        HStack { Stepper("Qty", value: .constant(1), in: 0...3); Spacer() }
    }
    .padding(Edges(all: px(16))).frame(width: px(400)).fixedSize(horizontal: false, vertical: true)
    let total = height(VStack { form })
    #expect(abs(total - 182.044) < 0.01, "the form is \(total) tall; FM0 reads 182.04")
}
