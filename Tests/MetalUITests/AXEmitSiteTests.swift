import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

// A declared `AXNode` is emitted by EVERY conformer that registers handlers —
// `Box.prepaint`, `Stack.prepaint` and `Text.prepaint`, the three element call
// sites of `PrepaintPass.registerHandlers`. `Column`, `Row` and `List` forward
// `prepaint` to a wrapped `Box` and so reach the `Box` arm.
//
// **Why a file of its own.** `Handlers.axNode` is a member of `handlers`, a
// `StyledElement` requirement, so it is settable on all six types. Until this
// file existed only `Box.prepaint` called `emitAXNode`: `Stack.prepaint` and
// `Text.prepaint` stopped at `registerHandlers`, so a node declared on either
// was dropped with no diagnostic — while `Stack.prepaint`'s own comment said
// its body mirrored `Box.prepaint` "line for line". The fix moved the gate
// (`!handlers.axNode.isEmpty`) into `Frame.registerHandlers`, so a conformer
// that registers handlers cannot also forget to emit.
//
// **The consequence at its true size is small, and this pin is about
// divergence rather than a user-visible defect.** Nothing in production reads
// an emitted node — `Frame.axNodes` and `Frame.axNode(for:)` have no reader
// until M4's bridge exists — no public modifier writes `Handlers.axNode`, and
// the demo sets none. What was wrong is that three conformers sharing one
// `handlers` requirement honoured one of its members on one of them, which is
// CLAUDE.md's declared-but-inert shape; `onClickIsLiveOnEveryConformerThatCanRegisterOne`
// (`InputDispatchTests.swift`) and `onKeyIsLiveOnEveryConformerThatCanRegisterOne`
// (`FocusTests.swift`) are this test's two elder siblings for the other members.
//
// **No Metal device.** `Frame.render` over a bare `Frame`, `AXNodeTests.swift`'s
// own footing — so, unlike the two siblings above, this runs on a runner with
// no display device.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: px(x), y: px(y)), size: Size(width: px(w), height: px(h)))
}

@MainActor private func rootID(_ name: String) -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: ElementID(name))
}

/// (Took an optional layout authority from stage 6b, `LR-DG`, until stage 9,
/// which deleted the legacy one.)
@MainActor private func render<E: Element>(_ element: inout E) -> Frame {
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)),
               scaleFactor: 1, stateTable: StateTable(),
               shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 256, height: 256),
               theme: Theme.forAppearance(.light))
    frame.render(&element)
    return frame
}

/// Renders `element` as the root with `node` declared on it and checks the
/// per-frame record AND the durable `$ax` copy. Records an issue rather than
/// throwing, so one silent arm cannot hide the arms after it.
@MainActor private func expectEmits<E: StyledElement>(_ name: String, _ element: E,
                                                      declaring node: AXNode,
                                                      at expectedBounds: Bounds<Pixels>) {
    var element = element
    element.handlers.axNode = node
    let frame = render(&element)
    let id = rootID(name)

    guard let emitted = frame.axNodes[id] else {
        Issue.record("\(name): declared an AXNode and emitted none — its prepaint registers handlers without emitting")
        return
    }
    #expect(emitted.role == node.role && emitted.label == node.label,
            "\(name): emitted \(emitted.role)/\(emitted.label ?? "nil"), declared \(node.role)/\(node.label ?? "nil")")
    #expect(emitted.frame == expectedBounds,
            "\(name): emitted at \(emitted.frame), its resolved bounds are \(expectedBounds)")

    guard let durable = frame.axNode(for: id) else {
        Issue.record("\(name): emitted into Frame.axNodes but wrote no $ax retention copy")
        return
    }
    #expect(durable.isValid && durable.label == node.label,
            "\(name): the $ax retention copy must be the node just emitted, and valid")
}

/// **Red on arrival for `stack` and `text`, green for the other four.** Every
/// arm declares a DIFFERENT role/label and a different non-square size, so an
/// emission under the wrong id, with a transposed width/height, or of another
/// arm's node is a mismatch rather than a coincidence (taxonomy shape 1). The
/// expected bounds are the declared sizes at the root's centred origin —
/// constants, not read back from layout (shape 12).
///
/// Stage 6b (`LR-DG`, R-centre): every root declares both axes, so under the
/// proposal authority it is centred in the 300x300 frame at its own answer
/// (`CN-J`): origin `((300 - w) / 2, (300 - h) / 2)`, rounded as
/// `roundLayout` rounds each edge (half away from zero, so an odd side's .5
/// origin rounds up and the width is kept): 41x23 at (130, 139), 43x29 at
/// (129, 136), 47x31 at (127, 135), 53x37 at (124, 132), 59x19 at (121, 141),
/// 61x17 at (120, 142), 55x37 at (123, 132); the inner layer 7 in from
/// (122.5, 131.5), so (130, 139).
@Test @MainActor func aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers() {
    expectEmits("box", Box().cssWidth(px(41)).cssHeight(px(23)).id("box"),
                declaring: AXNode(role: .button, label: "box-label"),
                at: rect(130, 139, 41, 23))
    expectEmits("column", Column { Box().cssWidth(px(10)).cssHeight(px(10)) }
                    .cssWidth(px(43)).cssHeight(px(29)).id("column"),
                declaring: AXNode(role: .container, label: "column-label"),
                at: rect(129, 136, 43, 29))
    expectEmits("row", Row { Box().cssWidth(px(10)).cssHeight(px(10)) }
                    .cssWidth(px(47)).cssHeight(px(31)).id("row"),
                declaring: AXNode(role: .generic, label: "row-label"),
                at: rect(127, 135, 47, 31))
    expectEmits("stack", Stack { Box().cssWidth(px(10)).cssHeight(px(10)) }
                    .cssWidth(px(53)).cssHeight(px(37)).id("stack"),
                declaring: AXNode(role: .image, label: "stack-label"),
                at: rect(124, 132, 53, 37))
    expectEmits("text", Text("Hi").cssWidth(px(59)).cssHeight(px(19)).id("text"),
                declaring: AXNode(role: .text, label: "text-label"),
                at: rect(121, 141, 59, 19))
    // `List` writes a `.container` node for itself when none is declared, so
    // this arm only shows that a DECLARED one reaches the frame through the
    // wrapped `Box` — `aCallerDeclaredAXNodeOnAListSurvivesLogicalCountBeingAdded`
    // (`AXNodeTests.swift`) owns the survival question.
    expectEmits("list", List([Datum(id: 0)], rowHeight: px(17)) { _ in Box() }
                    .cssWidth(px(61)).cssHeight(px(17)).id("list"),
                declaring: AXNode(role: .button, label: "list-label"),
                at: rect(120, 142, 61, 17))

    // Ruling MC-I: a `.padding`/`.frame` chain is ONE `ModifiedElement` that
    // registers each layer's handlers — and so emits each layer's declared
    // node — in a loop. Two arms over a two-layer chain. The outermost arm goes
    // through `expectEmits`, which declares the node on the outermost layer.
    expectEmits("modifiedOuter", Box().cssWidth(px(31)).cssHeight(px(13))
                    .padding(Edges(all: .pixels(px(5))))
                    .padding(Edges(all: .pixels(px(7))))
                    .cssWidth(px(55)).cssHeight(px(37)).id("modifiedOuter"),
                declaring: AXNode(role: .container, label: "modified-outer-label"),
                at: rect(123, 132, 55, 37))
    // The INNER arm declares its node on the padding-5 layer before the
    // padding-7 layer wraps it, so it is emitted under the inner layer's id,
    // `.positional(0)` under the root's. Its bounds, by hand: the outermost
    // layer is 55x37 with padding 7, so the inner layer starts at (7, 7) and is
    // 31 + 2x5 = 41 wide and 13 + 2x5 = 23 tall (the 37 - 2x7 = 23 a stretch
    // would give is the same number, so stretch cannot move it).
    do {
        var inner = Box().cssWidth(px(31)).cssHeight(px(13)).padding(Edges(all: .pixels(px(5))))
        inner.handlers.axNode = AXNode(role: .image, label: "modified-inner-label")
        var chain = inner.padding(Edges(all: .pixels(px(7)))).cssWidth(px(55)).cssHeight(px(37))
            .id("modifiedInner")
        let frame = render(&chain)
        let innerID = GlobalElementID.child(of: rootID("modifiedInner"), at: 0, name: nil)
        if let emitted = frame.axNodes[innerID] {
            #expect(emitted.role == .image && emitted.label == "modified-inner-label",
                    "modifiedInner: emitted \(emitted.role)/\(emitted.label ?? "nil")")
            #expect(emitted.frame == rect(130, 139, 41, 23),
                    "modifiedInner: emitted at \(emitted.frame), its resolved bounds are (130, 139, 41, 23)")
            #expect(frame.axNode(for: innerID)?.label == "modified-inner-label",
                    "modifiedInner: emitted into Frame.axNodes but wrote no $ax retention copy")
        } else {
            Issue.record("modifiedInner: the INNER layer declared an AXNode and emitted none — emitted ids \(Array(frame.axNodes.keys))")
        }
    }
}

/// **A non-root `Text`, off the origin on both axes — red on arrival.** The
/// root arms above all resolve to `(0, 0)`, which cannot tell "emitted at its
/// own absolute rect" from "emitted at the local origin". A `Row` 100 x 40 with
/// a 30 x 20 `Box` then a 20 x 10 `Text` puts the `Text` at x = 30 (after the
/// box; no gap) and y = (40 - 10) / 2 = 15 (EP-8: a `Row` centres its cross
/// axis). Hand-computed, not read off the engine.
///
/// Stage 6b (`LR-DG`, R-centre): the 100x40 root is centred in the 300x300
/// frame at ((300 - 100) / 2, (300 - 40) / 2) = (100, 130), so the `Text` is at
/// (130, 145).
@Test @MainActor func aNestedTextEmitsItsDeclaredAXNodeAtItsAbsoluteBounds() throws {
    var label = Text("Hi").cssWidth(px(20)).cssHeight(px(10)).id("label")
    label.handlers.axNode = AXNode(role: .text, label: "nested")
    var row = Row {
        Box().cssWidth(px(30)).cssHeight(px(20))
        label
    }.cssWidth(px(100)).cssHeight(px(40)).id("row")

    let frame = render(&row)
    let labelID = GlobalElementID.child(of: rootID("row"), at: 1, name: ElementID("label"))
    let node = try #require(frame.axNodes[labelID],
                            "a Text nested in a Row declared an AXNode and emitted none")
    #expect(node.role == .text && node.label == "nested")
    #expect(node.frame == rect(130, 145, 20, 10), "got \(node.frame)")
    #expect(frame.axNodes.count == 1,
            "only the Text declared a node; the Row and the Box declared none — got \(frame.axNodes.count)")
}

/// **The gate's other side, on every conformer the gate now serves.** A
/// conformer that declared nothing emits nothing — green before and after the
/// fix, and the control against a fold that dropped `isEmpty` and emitted an
/// empty node for every registering element. `List` is absent on purpose: it
/// always declares a `.container` node for itself.
@Test @MainActor func noConformerEmitsAnAXNodeItDidNotDeclare() {
    func expectSilent<E: Element>(_ name: String, _ element: E) {
        var element = element
        let frame = render(&element)
        #expect(frame.axNodes.isEmpty,
                "\(name): declared no AXNode but emitted \(frame.axNodes.count)")
    }
    expectSilent("box", Box().cssWidth(px(41)).cssHeight(px(23)).id("box"))
    expectSilent("column", Column { Box().cssWidth(px(10)).cssHeight(px(10)) }
                    .cssWidth(px(43)).cssHeight(px(29)).id("column"))
    expectSilent("row", Row { Box().cssWidth(px(10)).cssHeight(px(10)) }
                    .cssWidth(px(47)).cssHeight(px(31)).id("row"))
    expectSilent("stack", Stack { Text("Hi") }.cssWidth(px(53)).cssHeight(px(37)).id("stack"))
    expectSilent("text", Text("Hi").cssWidth(px(59)).cssHeight(px(19)).id("text")
                    .onClick {}.focusable())
}

private struct Datum: Identifiable { let id: Int }
