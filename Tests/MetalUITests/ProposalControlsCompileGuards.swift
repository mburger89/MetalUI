import Testing
import MetalUITestSupport

// Spec `docs/superpowers/specs/2026-10-06-proposal-controls-design.md` §6.1,
// tests 1.2, 1.3 and 1.21 (rulings `PE-B`, `PE-E`, `PE-F`, `PE-R` in
// `docs/superpowers/2026-10-06-proposal-controls-decisions.md`): what an
// EXTERNAL module may write inside a SwiftUI-vocabulary container once its
// content closure is a `ProposalContentBuilder`.
//
// **Every fixture is `typecheckFile` against a PLAIN `import MetalUI`** (ruling
// SA-P): a `@testable` test cannot see an access level or a missing overload.
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `PROPOSAL CONTROLS GUARD` to know
// these ran. Each prints the compiler's messages before asserting on them, and
// each has a separating arm that must fail, `#require`d to disagree with the
// positive.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func show(_ label: String, _ result: TypecheckResult) {
    print("PROPOSAL CONTROLS GUARD \(label): succeeded=\(result.succeeded)\n\(result.messages)")
}

/// **1.2** (`PE-B`). Proposal content keeps its type through
/// `ProposalContentBuilder` — `HStack { Spacer(); Rectangle() }` is still
/// `HStack<Pair<Spacer, Rectangle>>`, so the typed builder copies (`MC-H`) are
/// still the ones a stack reaches — and a legacy expression is adopted as
/// `LegacyContent<_>`, per expression statement. The separating arm: a proposal
/// expression is NOT wrapped (`HStack<LegacyContent<Spacer>>` must fail).
///
/// Red before: `LegacyContent` does not exist. Mutation M1.2 (delete the
/// `ProposalElementGroup` `buildExpression` overload) wraps the first line's
/// `Spacer` and `Rectangle`, so the positive fails.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func proposalContentKeepsItsTypeAndLegacyContentIsAdopted() throws {
    let positive = try typecheckFile("""
        @MainActor public func typed() {
            let _: HStack<Pair<Spacer, Rectangle>> = HStack { Spacer(); Rectangle() }
            let _: HStack<Pair<LegacyContent<Text>, Spacer>> = HStack { Text("a"); Spacer() }
        }
        """, importing: "MetalUI")
    show("1.2 positive", positive)
    let control = try typecheckFile("""
        @MainActor public func wrapped() {
            let _: HStack<LegacyContent<Spacer>> = HStack { Spacer() }
        }
        """, importing: "MetalUI")
    show("1.2 control", control)
    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "proposal content keeps its type, legacy content is adopted:\n\(positive.output)")
    #expect(!control.succeeded, "a proposal expression must not be wrapped:\n\(control.output)")
}

/// The body of test 1.3's form: every container, control, builder construct and
/// modifier the item names, as a SwiftUI port writes them. `CONTAINER` is
/// replaced by the outer container's spelling.
private let formSource = """
    public enum Pane: Sendable { case general, keys, about }

    public struct Item: Identifiable, Sendable {
        public let id: Int
        public init(id: Int) { self.id = id }
    }

    public struct Badge: Component {
        public init() {}
        @State var count = 0
        public var content: some ElementGroup {
            Text("\\(count)")
            Button("+") { count += 1 }
        }
    }

    public struct FirstOnly: ProposalLayout {
        public init() {}
        public func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
            subviews[0].sizeThatFits(proposal)
        }
        public func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
            for subview in subviews { subview.place(at: Point(x: bounds.x, y: bounds.y), proposal: proposal) }
        }
    }

    @MainActor public func form(_ flag: Bool, _ pane: Pane, _ names: [String], _ items: [Item],
                                name: Binding<String>, notes: Binding<String>, on: Binding<Bool>,
                                speed: Binding<Double>, flavour: Binding<Int>, quantity: Binding<Int>,
                                selected: Binding<Int?>) -> some Element {
        CONTAINER {
            HStack {
                Text("Name").font(.system(size: 11))
                TextField("Name", text: name).frame(maxWidth: .infinity)
            }
            HStack {
                Toggle("Enabled", isOn: on).help("Turns it on")
                Spacer()
                Button("Apply") {}.keyboardShortcut(.defaultAction).frame(width: 120)
                Button("Plain") {}.buttonStyle(.plain).onHover { _ in }.disabled(true)
            }
            HStack(spacing: 8) {
                Text("A much longer label").layoutPriority(1)
                Slider(value: speed)
                Stepper("Qty", value: quantity, in: 0...10).padding(8)
            }
            ZStack {
                Picker("Flavour", selection: flavour) { Text("A").tag(0); Text("B").tag(1) }
                    .pickerStyle(.segmented)
                Picker("Menu", selection: flavour) { Text("A").tag(0); Text("B").tag(1) }
                    .pickerStyle(.menu)
                Picker("Radio", selection: flavour) { Text("A").tag(0); Text("B").tag(1) }
                    .pickerStyle(.radioGroup)
            }
            Grid {
                GridRow {
                    Text("Notes").fixedSize()
                    TextEditor("Notes", text: notes)
                }
                GridRow {
                    Menu("Actions") { Button("Copy") {} }.gridCellColumns(2)
                }
            }
            Divider()
            if flag {
                Text("on")
            } else {
                Badge()
            }
            switch pane {
            case .general: Text("General")
            case .keys: Button("Keys") {}
            case .about: Rectangle()
            }
            for name in names {
                Text(name)
            }
            ForEach(items) { item in
                Text("\\(item.id)")
            }
            ProposalScrollView {
                VStack {
                    List(items, selection: selected, rowHeight: 20) { item in Text("\\(item.id)") }
                }
            }
            FirstOnly() {
                Badge()
                Text("first")
            }
            Spacer()
        }
    }
    """

/// **1.3** (`PE-B`, `PE-E`, `PE-F`). One file, plain import: an `HStack`/
/// `VStack`/`ZStack`/`Grid`/`GridRow`/`ProposalScrollView`/custom-layout tree
/// holding `Text`, `Button`, `Toggle`, `TextField`, `TextEditor`, `Picker`
/// (three styles), `Slider`, `Stepper`, `Menu`, `List(selection:)`, `Divider`,
/// `Spacer`, an `if`/`else`, a `switch`, a `for`, a `ForEach` and a legacy
/// `Component`, with the control modifiers a port writes (`.frame(width:)`,
/// `.frame(maxWidth: .infinity)`, `.padding(8)`, `.disabled(true)`, `.help`,
/// `.keyboardShortcut(.defaultAction)`, `.buttonStyle(.plain)`,
/// `.pickerStyle(_:)`, `.onHover`, `.layoutPriority(1)`, `.fixedSize()`,
/// `.gridCellColumns(2)`, `.font(.system(size: 11))`), typechecks.
///
/// Two separating arms: (1) the same body inside `ProposalFrame { }` — a native
/// wrapper that keeps `@ElementBuilder` (`PE-E`) — fails naming
/// `ProposalElementGroup`; (2) `PE-R`: a style modifier is written on the
/// control, so `Button("x") {}.padding(8).buttonStyle(.plain)` — a wrapper,
/// then the style — fails. (Spelled `.padding(8)`, not the spec's
/// `.padding(Edges(all: 8))`: measured before this lane, that spelling fails
/// twice — `Edges<Int>` is not `Pixels`, then no `buttonStyle` — and the arm
/// should fail for the one reason it is about.)
///
/// Red before: fails (legacy content in every container). Mutation M1.3
/// (`GridRow` back to `@ElementBuilder`) reddens it.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aSwiftUIVocabularyFormTypechecksWithAPlainImport() throws {
    let positive = try typecheckFile(formSource.replacingOccurrences(of: "CONTAINER",
                                                                     with: "VStack(alignment: .leading)"),
                                     importing: "MetalUI")
    show("1.3 positive", positive)
    let wrapper = try typecheckFile(formSource.replacingOccurrences(of: "CONTAINER", with: "ProposalFrame"),
                                    importing: "MetalUI")
    show("1.3 control ProposalFrame", wrapper)
    let style = try typecheckFile("""
        @MainActor public func styled() {
            _ = HStack { Button("x") {}.padding(8).buttonStyle(.plain) }
        }
        """, importing: "MetalUI")
    show("1.3 control PE-R wrapper-then-style", style)

    try #require(positive.succeeded != wrapper.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(wrapper.output)")
    #expect(positive.succeeded, "a SwiftUI-vocabulary form must typecheck:\n\(positive.output)")
    #expect(!wrapper.succeeded, "a native wrapper must still reject legacy content:\n\(wrapper.output)")
    #expect(wrapper.messages.contains("ProposalElementGroup"),
            "rejected, but not for the proposal marker:\n\(wrapper.output)")
    #expect(!style.succeeded, "PE-R: a style modifier after a wrapper must not compile:\n\(style.output)")
    #expect(style.messages.contains("buttonStyle"),
            "rejected, but not for the missing style modifier:\n\(style.output)")
}

/// **1.21** (`PE-F` item 2; probe FL21, `Toggle("Wi-Fi").frame(maxWidth:
/// .infinity)`, greedy `inf -> infx16.42`). SwiftUI's `.frame(maxWidth: .infinity)` compiles
/// on a legacy element and on a proposal element through `Pixels.infinity`.
/// Separating arm: an unknown member, `.greatest`, fails — so the positive is
/// not satisfied by some other inference.
///
/// Red before: `Pixels` has no `infinity`. Mutation M1.21 (delete
/// `Pixels.infinity`) reddens it.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func pixelsInfinityIsSwiftUIsFrameSpelling() throws {
    let positive = try typecheckFile("""
        @MainActor public func frames() {
            _ = Text("legacy").frame(maxWidth: .infinity)
            _ = Rectangle().frame(maxWidth: .infinity)
            let infinite: Pixels = .infinity
            _ = infinite
        }
        """, importing: "MetalUI")
    show("1.21 positive", positive)
    let control = try typecheckFile("""
        @MainActor public func frames() {
            _ = Text("legacy").frame(maxWidth: .greatest)
        }
        """, importing: "MetalUI")
    show("1.21 control", control)
    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, ".frame(maxWidth: .infinity) must compile:\n\(positive.output)")
    #expect(!control.succeeded, "an unknown member must not:\n\(control.output)")
}
