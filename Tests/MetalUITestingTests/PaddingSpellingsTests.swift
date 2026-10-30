import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Ruling `DX-B`: SwiftUI's padding spellings lay out the same on `Text`, `ProposalText` and a
// stack. Native arms (no goldens): frames by `.id`, measured as the difference from the
// unpadded twin so no font metric is a literal.

private func size(_ b: Bounds<Pixels>) -> [Float] { [b.size.width.value, b.size.height.value] }

/// (Insets are even: a centred root's origin is rounded, and an odd growth shifts it by a half point.)
/// Padded and plain frames of `Text("Padded")` under `pad`, as (padded − plain) width and height, and the
/// padded frame's origin shift against the plain one (a centred root moves by half the growth).
@MainActor private func textGrowth<R: Element>(_ pad: @escaping @MainActor (Text) -> R) throws -> [Float] {
    let plain = try harnessWindow { VStack(spacing: 0) { Text("Padded").id("t") } }
    let padded = try harnessWindow { VStack(spacing: 0) { pad(Text("Padded")).id("t") } }
    let a = try plain.frame(ofID: "t"), b = try padded.frame(ofID: "t")
    return [b.size.width.value - a.size.width.value, b.size.height.value - a.size.height.value]
}

@MainActor private func proposalGrowth<R: ProposalElementGroup>(_ pad: @escaping @MainActor (ProposalText) -> R) throws -> [Float] {
    let plain = try harnessWindow { VStack(spacing: 0) { HStack { ProposalText("Padded") }.id("t") } }
    let padded = try harnessWindow { VStack(spacing: 0) { HStack { pad(ProposalText("Padded")) }.id("t") } }
    let a = try plain.frame(ofID: "t"), b = try padded.frame(ofID: "t")
    return [b.size.width.value - a.size.width.value, b.size.height.value - a.size.height.value]
}

/// **DX-B 1.** `Text` takes SwiftUI's spellings: a length, edges plus a length, `EdgeInsets`, and the
/// points-per-edge `Edges<Pixels>` a stack takes. Red before: all but the first did not compile (the
/// guard `theTextAndStackPaddingSpellingsCompile`), so this file did not build. Mutations: **MX-F**
/// `Edge.Set.insets` swaps leading and trailing (the asymmetric arm); **MX-G** `StyledElement`'s
/// `Edges<Pixels>` form drops the bottom edge; **MX-H** `EdgeInsets.edges` swaps top and bottom.
@Test @MainActor func textTakesTheSwiftUIPaddingSpellings() throws {
    #expect(try textGrowth { $0.padding(8) } == [16, 16])
    #expect(try textGrowth { $0.padding(.horizontal, 8) } == [16, 0])
    #expect(try textGrowth { $0.padding(.vertical, 5) } == [0, 10])
    #expect(try textGrowth { $0.padding([.leading, .top], 4) } == [4, 4])
    #expect(try textGrowth { $0.padding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)) } == [6, 4])
    #expect(try textGrowth { $0.padding(Edges<Pixels>(top: 1, right: 4, bottom: 3, left: 2)) } == [6, 4])
    #expect(try textGrowth { $0.padding(Edges(all: .pixels(2))) } == [4, 4], "the Length form is unchanged")
}

/// **DX-B 2.** The same spellings on a stack and on `ProposalText` grow by the same amounts as `Text`,
/// which is the parity the report asked for. Mutation: **MX-I** drop `ProposalElementGroup.padding(_: Pixels)`
/// (does not compile; the arm exists to be the reader of that overload).
@Test @MainActor func aStackAndProposalTextTakeTheSameSpellingsWithTheSameGrowth() throws {
    #expect(try proposalGrowth { $0.padding(8) } == [16, 16])
    #expect(try proposalGrowth { $0.padding(.horizontal, 8) } == [16, 0])
    #expect(try proposalGrowth { $0.padding(.vertical, 5) } == [0, 10])
    #expect(try proposalGrowth { $0.padding([.leading, .top], 4) } == [4, 4])
    #expect(try proposalGrowth { $0.padding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)) } == [6, 4])
    #expect(try proposalGrowth { $0.padding(Edges<Pixels>(top: 1, right: 4, bottom: 3, left: 2)) } == [6, 4])
}

/// **DX-B 3.** Leading is the left edge and trailing the right: a fixed box padded `.leading, 30` sits 30
/// right of its padded frame's origin on a stack, and `.trailing` leaves it flush left.
@Test @MainActor func leadingPaddingPushesTheContentRightOnAStack() throws {
    let window = try harnessWindow {
        HStack(spacing: 0) {
            HStack(spacing: 0) { Box().frame(width: Pixels(40), height: Pixels(20)).id("a") }
                .padding(.leading, 30).id("A")
            HStack(spacing: 0) { Box().frame(width: Pixels(40), height: Pixels(20)).id("b") }
                .padding(.trailing, 30).id("B")
        }
    }
    let A = try window.frame(ofID: "A"), a = try window.frame(ofID: "a")
    let B = try window.frame(ofID: "B"), b = try window.frame(ofID: "b")
    #expect(size(A) == [70, 20] && a.origin.x.value - A.origin.x.value == 30)
    #expect(size(B) == [70, 20] && b.origin.x.value - B.origin.x.value == 0)
}

/// **DX-B 3b.** `EdgeInsets` puts each inset on its own edge: a box in a stack padded top 10, leading 2, bottom 4,
/// trailing 6 sits 10 down and 2 right of the padded frame, which is 8 wider and 14 taller. Mutation **MX-H**
/// (`EdgeInsets.edges` swaps top and bottom) is green on the growth sums alone and red here.
@Test @MainActor func edgeInsetsPutEachInsetOnItsOwnEdge() throws {
    let window = try harnessWindow {
        VStack(spacing: 0) {
            HStack(spacing: 0) { Box().frame(width: Pixels(40), height: Pixels(20)).id("in") }
                .padding(EdgeInsets(top: 10, leading: 2, bottom: 4, trailing: 6)).id("out")
        }
    }
    let out = try window.frame(ofID: "out"), inner = try window.frame(ofID: "in")
    #expect(size(out) == [48, 34])
    #expect(inner.origin.x.value - out.origin.x.value == 2 && inner.origin.y.value - out.origin.y.value == 10)
}

/// **DX-B 4.** A `Component` over proposal content keeps `Component.padding(_:)` (the overload that settles
/// the ambiguity `LayoutAuthorityTests` found): padded, it is still `StyledComponent`. Mutation: **MX-J**
/// delete `extension Component where Self: ProposalElementGroup` (the build then fails with `ambiguous use
/// of 'padding'` at `LayoutAuthorityTests.swift`'s Component-wrap arm).
@Test @MainActor func aProposalComponentsPaddingStaysTheComponents() {
    struct C: Component { var content: some ProposalElementGroup { ProposalText("x") } }
    let padded: StyledComponent<C> = C().padding(4)
    _ = padded
}

/// **DX-B 5.** `.padding(8).background(color)` on `Text` paints the colour over the padded frame, the order an
/// app writes: the rect is the text's size plus the padding on both axes.
@Test @MainActor func aBackgroundAfterTextPaddingFillsThePaddedFrame() throws {
    let plain = try harnessWindow { VStack(spacing: 0) { Text("Padded").id("t") } }
    let window = try harnessWindow { VStack(spacing: 0) { Text("Padded").padding(8).background(Color(red: 1, green: 0, blue: 0)).id("t") } }
    let base = try plain.frame(ofID: "t"), frame = try window.frame(ofID: "t")
    #expect(size(frame) == [base.size.width.value + 16, base.size.height.value + 16])
    let fills = window.scene.rects.filter {
        $0.bounds.size.width == frame.size.width.value && $0.bounds.size.height == frame.size.height.value
    }
    #expect(!fills.isEmpty, "a rect of the padded size is painted")
}
