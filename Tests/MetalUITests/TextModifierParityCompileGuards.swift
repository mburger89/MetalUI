import Testing
import MetalUITestSupport

// Text and stack padding parity — what an app writes (ruling `DX-B`). `typecheckFile` with a plain
// `import MetalUI` (`SA-P`). **A guard skips silently when `.build/<triple>/debug/Modules` is absent**;
// grep the log for `DX GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **DX-B G1.** The spellings SwiftUI offers compile on `Text`, `ProposalText` and a stack alike, in the
/// order an app writes them (`padding` then `background`, and the reverse). Red before: `Text` had no
/// `Edges<Pixels>`/`Edge.Set`/`EdgeInsets` form, a stack and `ProposalText` had no single-length form, and
/// no type had the `Edge.Set` forms. Mutations: **MX-K** delete `StyledElement.padding(_: Edges<Pixels>)`;
/// **MX-L** delete `ProposalElementGroup.padding(_ length:)`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theTextAndStackPaddingSpellingsCompile() throws {
    let compiles = try typecheckFile("""
        @MainActor public func text() {
            _ = Text("x").padding(8).background(Color(.surface))
            _ = Text("x").background(Color(.surface)).padding(8)
            _ = Text("x").padding(.horizontal, 8)
            _ = Text("x").padding([.top, .leading], 4)
            _ = Text("x").padding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
            _ = Text("x").padding(Edges(all: 8))
            _ = Text("x").padding(Edges<Pixels>(top: 1, right: 2, bottom: 3, left: 4))
            _ = Text("x").padding(Edges<Length>(all: .pixels(8)))
        }
        @MainActor public func proposal() {
            _ = ProposalText("x").padding(8).background(Color(.surface))
            _ = ProposalText("x").padding(.vertical, 8)
            _ = HStack { ProposalText("x") }.padding(8)
            _ = HStack { ProposalText("x") }.padding(.horizontal, 8).background(Color(.surface))
            _ = HStack { ProposalText("x") }.padding(EdgeInsets())
            _ = HStack { ProposalText("x") }.padding(Edges(all: 8))
            _ = HStack { Text("x").padding(8).background(Color(.surface)) }
        }
        @MainActor struct Legacy: Component { var content: some ElementGroup { Text("x") } }
        @MainActor struct Proposal: Component { var content: some ProposalElementGroup { ProposalText("x") } }
        @MainActor public func components() {
            let a: StyledComponent<Legacy> = Legacy().padding(8)
            let b: StyledComponent<Proposal> = Proposal().padding(8)
            _ = (a, b)
        }
        """, importing: "MetalUI")
    print("DX GUARD G1 compiles: succeeded=\(compiles.succeeded) messages=[\(compiles.messages)]")
    #expect(compiles.succeeded, "SwiftUI's padding spellings must compile on both vocabularies:\n\(compiles.output)")
}

/// **DX-B G2.** What stays out, by name (divergence 208): the default-edges and default-length spellings and a
/// `Component`'s edge form. Mutation: **MX-M** give `padding(_:_:)` a default edge set.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSystemDefaultPaddingSpellingsStayAbsent() throws {
    let refusals: [(String, String)] = [
        ("padding()", "@MainActor public func probe() { _ = Text(\"x\").padding() }"),
        ("padding(.horizontal)", "@MainActor public func probe() { _ = Text(\"x\").padding(.horizontal) }"),
        ("stack padding()", "@MainActor public func probe() { _ = HStack { ProposalText(\"x\") }.padding() }"),
        ("a Component's edge form", """
            @MainActor struct C: Component { var content: some ElementGroup { Text("x") } }
            @MainActor public func probe() { _ = C().padding(.horizontal, 8) }
            """),
    ]
    for (name, source) in refusals {
        let result = try typecheckFile(source, importing: "MetalUI")
        print("DX GUARD G2 \(name): succeeded=\(result.succeeded)")
        #expect(!result.succeeded, "\(name) must not compile (divergence 208)")
    }
}
