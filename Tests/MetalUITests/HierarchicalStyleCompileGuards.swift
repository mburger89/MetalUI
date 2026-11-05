import Testing
import MetalUITestSupport

// Round 4 item R4-4 PR A (`HY-`, divergence 119): whole-file Swift 6 against a PLAIN `import MetalUI`
// (`typecheckFile`, ruling SA-P). A leading-dot `.secondary` must infer `HierarchicalShapeStyle` at every
// colour-taking sink while `.red`, `.accentColor`, `Color.secondary`, a `Color` variable, a `ColorToken`
// and `.tint` keep binding as they did, with no ambiguity. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log for `HIERARCHICAL GUARD`.
//
// A typecheck guard sees acceptance, not WHICH overload bound (every arm returns one type), so the binding
// itself is pinned by pixels in `HierarchicalStylePaintTests`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G-HY1 — every overload arm compiles with no ambiguity.** For each sink (`Shape`/`ShapeView` `fill`,
/// `stroke`, `strokeBorder` in both parameter shapes, `background(_:in:)`, `background(_:)` and `border` on a
/// legacy `Box` and on proposal content, and `foregroundStyle` on a group, `Text` and `ProposalText`): the five
/// levels, a `Color` literal (`.red`), `.accentColor`, `Color.secondary`, a `Color` variable, a token literal and
/// variable, `.tint`, an erased and a generic style, a gradient and a material, and four ternaries
/// (`flag ? .secondary : .primary`, `flag ? .red : .blue`, `flag ? Color.red : .secondary`,
/// `flag ? .red : .secondary`). Negative arms are each their own fixture: a level is no `Color`, and a
/// misspelt level is no style.
///
/// Mutations that must redden it or the build: `@_disfavoredOverload` removed from a sink's `Color`
/// overload (the level then ties with `Color.secondary`), or from its generic one (the level ties with the
/// concrete level overload), or the level overload deleted at one sink.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func everyHierarchicalOverloadArmTypechecksWithoutAmbiguity() throws {
    let positive = try typecheckFile("""
        @MainActor func shapes(_ flag: Bool, _ c: Color, _ t: ColorToken, _ s: some ShapeStyle,
                               _ any: AnyShapeStyle, _ g: LinearGradient) {
            let w = Pixels(2)
            let stroke = StrokeStyle(lineWidth: w)
            // Levels.
            _ = Rectangle().fill(.primary).fill(.secondary).fill(.tertiary).fill(.quaternary).fill(.quinary)
            _ = Rectangle().fill(.secondary, style: FillStyle())
            _ = Rectangle().stroke(.secondary, lineWidth: w).stroke(.tertiary, style: stroke)
            _ = Rectangle().strokeBorder(.secondary, lineWidth: w).strokeBorder(.quaternary, style: stroke)
            // The same sites, one `fill` first so the receiver is a `ShapeView`.
            _ = Rectangle().fill(.red).fill(.secondary).fill(.secondary, style: FillStyle())
                .stroke(.secondary, lineWidth: w).stroke(.secondary, style: stroke)
                .strokeBorder(.secondary, lineWidth: w).strokeBorder(.secondary, style: stroke)
            // Colours.
            _ = Rectangle().fill(.red).fill(.accentColor).fill(Color.secondary).fill(Color.primary).fill(c)
            _ = Rectangle().fill(.red, style: FillStyle()).fill(c, style: FillStyle())
            _ = Rectangle().stroke(.red, lineWidth: w).stroke(c, lineWidth: w).stroke(Color.secondary, style: stroke)
            _ = Rectangle().strokeBorder(.red, lineWidth: w).strokeBorder(c, style: stroke)
            _ = Rectangle().fill(.red).fill(.accentColor).stroke(.red, lineWidth: w).strokeBorder(.red, style: stroke)
            // Tokens, `.tint`, erased, generic, gradient, material.
            _ = Rectangle().fill(.textPrimary).fill(.accent).fill(t).stroke(.separator, lineWidth: w).stroke(t, style: stroke)
            _ = Rectangle().strokeBorder(.accent, lineWidth: w).strokeBorder(t, lineWidth: w)
            _ = Rectangle().fill(.tint).fill(s).fill(any).fill(g).fill(Material.regularMaterial).fill(.regularMaterial)
            _ = Rectangle().stroke(.tint, lineWidth: w).stroke(s, lineWidth: w).stroke(any, style: stroke)
            _ = Rectangle().fill(AnyShapeStyle(.secondary)).fill(AnyShapeStyle(Color.red))
            // Ternaries.
            _ = Rectangle().fill(flag ? .secondary : .primary).fill(flag ? .secondary : .tertiary)
            _ = Rectangle().fill(flag ? .red : .blue).fill(flag ? Color.red : .secondary).fill(flag ? .red : .secondary)
            _ = Rectangle().stroke(flag ? .secondary : .primary, lineWidth: w)
            _ = Rectangle().stroke(flag ? .red : .blue, lineWidth: w).stroke(flag ? .red : .secondary, style: stroke)
            _ = Rectangle().strokeBorder(flag ? .secondary : .primary, lineWidth: w)
            _ = Rectangle().strokeBorder(flag ? Color.red : .secondary, style: stroke)
        }

        @MainActor func groups(_ flag: Bool, _ c: Color, _ t: ColorToken, _ s: some ShapeStyle,
                               _ any: AnyShapeStyle, _ g: LinearGradient) {
            let w = Pixels(2)
            // `foregroundStyle` on a group, on `Text` and on `ProposalText` (the two own spellings return
            // their own type; an `ElementGroup` fallback would otherwise accept a deleted overload).
            _ = Column { Text("a") }.foregroundStyle(.primary).foregroundStyle(.secondary).foregroundStyle(.tertiary)
                .foregroundStyle(.quaternary).foregroundStyle(.quinary)
            _ = Column { Text("a") }.foregroundStyle(.red).foregroundStyle(.accentColor).foregroundStyle(Color.secondary)
                .foregroundStyle(c).foregroundStyle(.textPrimary).foregroundStyle(t).foregroundStyle(.tint)
                .foregroundStyle(s).foregroundStyle(any).foregroundStyle(g).foregroundStyle(.regularMaterial)
            _ = Column { Text("a") }.foregroundStyle(flag ? .secondary : .primary).foregroundStyle(flag ? .red : .blue)
                .foregroundStyle(flag ? Color.red : .secondary).foregroundStyle(flag ? .red : .secondary)
            _ = Box { Text("a") }.foregroundStyle(.secondary).foregroundStyle(.red).foregroundStyle(t)
            let _: Text = Text("a").foregroundStyle(.secondary)
            let _: Text = Text("a").foregroundStyle(.quinary)
            let _: Text = Text("a").foregroundStyle(.red)
            let _: Text = Text("a").foregroundStyle(.accentColor)
            let _: Text = Text("a").foregroundStyle(Color.secondary)
            let _: Text = Text("a").foregroundStyle(c)
            let _: Text = Text("a").foregroundStyle(.textPrimary)
            let _: Text = Text("a").foregroundStyle(t)
            let _: Text = Text("a").foregroundStyle(.tint)
            let _: Text = Text("a").foregroundStyle(any)
            let _: Text = Text("a").foregroundStyle(s)
            let _: Text = Text("a").foregroundStyle(g)
            let _: Text = Text("a").foregroundStyle(flag ? .secondary : .primary)
            let _: Text = Text("a").foregroundStyle(flag ? .red : .blue)
            let _: Text = Text("a").foregroundStyle(flag ? Color.red : .secondary)
            let _: Text = Text("a").foregroundStyle(flag ? .red : .secondary)
            let _: ProposalText = ProposalText("a").foregroundStyle(.secondary)
            let _: ProposalText = ProposalText("a").foregroundStyle(.red)
            let _: ProposalText = ProposalText("a").foregroundStyle(.accentColor)
            let _: ProposalText = ProposalText("a").foregroundStyle(Color.secondary)
            let _: ProposalText = ProposalText("a").foregroundStyle(c)
            let _: ProposalText = ProposalText("a").foregroundStyle(.textPrimary)
            let _: ProposalText = ProposalText("a").foregroundStyle(t)
            let _: ProposalText = ProposalText("a").foregroundStyle(.tint)
            let _: ProposalText = ProposalText("a").foregroundStyle(any)
            let _: ProposalText = ProposalText("a").foregroundStyle(s)
            let _: ProposalText = ProposalText("a").foregroundStyle(flag ? .secondary : .primary)
            let _: ProposalText = ProposalText("a").foregroundStyle(flag ? .red : .secondary)
            // The tint keeps its `Color?` overload.
            _ = Column { Text("a") }.tint(.red).tint(.secondary).tint(c).tint(nil as Color?).tint(.accentColor)
            // `background(_:in:)` on a group.
            _ = Column { Text("a") }.background(.secondary, in: Circle()).background(.red, in: Circle())
                .background(.surface, in: Circle()).background(t, in: Circle()).background(c, in: Circle())
                .background(.tint, in: Circle()).background(s, in: Circle()).background(any, in: Circle())
                .background(flag ? .secondary : .primary, in: Circle()).background(flag ? .red : .secondary, in: Circle())
            // `background` and `border` on a legacy `Box`.
            _ = Box().background(.secondary).background(.quaternary).background(.red).background(c).background(.surface)
                .background(t).background(.tint).background(s).background(any).background(g)
                .background(Material.regularMaterial)
            _ = Box().background(flag ? .secondary : .primary).background(flag ? .red : .blue)
                .background(flag ? Color.red : .secondary).background(flag ? .red : .secondary)
            _ = Box().border(.secondary, width: w).border(.red, width: w).border(c, width: w).border(.separator, width: w)
                .border(t, width: w).border(.tint, width: w).border(s, width: w).border(any, width: w)
            _ = Box().border(.secondary, widths: Edges(all: w)).border(.red, widths: Edges(all: w))
                .border(c, widths: Edges(all: w)).border(t, widths: Edges(all: w))
            _ = Box().border(flag ? .secondary : .primary, width: w).border(flag ? .red : .secondary, width: w)
        }

        @MainActor func proposal(_ flag: Bool, _ c: Color, _ t: ColorToken, _ s: some ShapeStyle,
                                 _ any: AnyShapeStyle, _ g: LinearGradient) {
            let w = Pixels(2)
            let leaf = Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(40), height: Pixels(40))
            _ = leaf.background(.secondary).background(.primary).background(.quinary)
            _ = leaf.background(.red).background(.accentColor).background(Color.secondary).background(c)
                .background(.surface).background(t).background(.tint).background(s).background(any).background(g)
                .background(Material.regularMaterial)
            _ = leaf.background(flag ? .secondary : .primary).background(flag ? .red : .blue)
                .background(flag ? Color.red : .secondary).background(flag ? .red : .secondary)
            _ = leaf.border(.secondary, width: w).border(.red, width: w).border(c, width: w).border(.separator, width: w)
                .border(t, width: w).border(.tint, width: w).border(s, width: w).border(any, width: w)
            _ = leaf.border(.secondary, width: w, cornerRadius: w).border(.red, width: w, cornerRadius: w)
            _ = leaf.border(flag ? .secondary : .primary, width: w).border(flag ? .red : .secondary, width: w)
        }

        @MainActor func explicitSpellings(_ s: some ShapeStyle) {
            let a: HierarchicalShapeStyle = .secondary
            let b: HierarchicalShapeStyle = HierarchicalShapeStyle.quinary
            let c: some ShapeStyle = HierarchicalShapeStyle.primary
            _ = [a, b, .primary, .tertiary, .quaternary]
            _ = Rectangle().fill(a).stroke(b, lineWidth: Pixels(1)).fill(c).fill(s)
            _ = Column { Text("a") }.foregroundStyle(a).background(b, in: Circle())
            _ = a == b
            _ = Set([a, b]).count
        }
        """, importing: "MetalUI")
    print("HIERARCHICAL GUARD G-HY1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let levelIsNoColor = try typecheckFile("""
        func f() { let _: Color = HierarchicalShapeStyle.secondary }
        """, importing: "MetalUI")
    let noSuchLevel = try typecheckFile("""
        @MainActor func f() { _ = Rectangle().fill(.senary) }
        """, importing: "MetalUI")
    let levelIsNoToken = try typecheckFile("""
        func f() { let _: ColorToken = HierarchicalShapeStyle.secondary }
        """, importing: "MetalUI")
    print("HIERARCHICAL GUARD G-HY1 negatives: levelIsNoColor=\(levelIsNoColor.succeeded) "
          + "noSuchLevel=\(noSuchLevel.succeeded) levelIsNoToken=\(levelIsNoToken.succeeded)")
    try #require(positive.succeeded && !levelIsNoColor.succeeded && !noSuchLevel.succeeded && !levelIsNoToken.succeeded,
                 """
                 the arms must disagree, or the guard measures nothing:
                 \(positive.output)
                 \(levelIsNoColor.output)
                 \(noSuchLevel.output)
                 \(levelIsNoToken.output)
                 """)
    #expect(levelIsNoColor.messages.contains("cannot convert"), "\(levelIsNoColor.output)")
    #expect(noSuchLevel.messages.contains("senary"), "\(noSuchLevel.output)")
}
