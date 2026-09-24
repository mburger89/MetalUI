import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func sized(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: .length(.pixels(px(w))), height: .length(.pixels(px(h))))
    return s
}

/// A frame under `authority`, with diagnostics on under the proposal one so a
/// field with no lowering is a report the test reads rather than a trap that
/// ends the run (`LR-BX`).
@MainActor
private func authorityFrame(_ w: Float, _ h: Float, _ authority: LayoutAuthority,
                            table: StateTable = StateTable()) -> Frame {
    Frame(contentSize: Size(width: px(w), height: px(h)), scaleFactor: 1,
          stateTable: table, theme: Theme.forAppearance(.light),
          layoutAuthority: authority, reportsUnlowerableFields: authority == .proposal)
}

/// Lays `element` out inside a window-sized, cross-stretching **row** `Box` over
/// `table` — the host a scroller that must really scroll needs (`LR-CO`, corrected
/// by stage 5 lane 2's `LR-CR`). `DifferentialRoot`'s legacy stack offers its
/// child fit-content, so a viewport under it hugs its content and never scrolls.
///
/// **A row, not the column the design named** (`ListTests`' `hostStyle`):
/// measured, a legacy `ScrollView` that is a column host's direct child keeps its
/// content's height — its viewport node is `flexShrink: 0` (`ScrollView.swift`'s
/// table) — so in 2.5's column host its region was clipped to 200×70 while its
/// `viewportExtent` read **300** and the offset of 40 clamped to 0: the in-flow
/// marker stayed at y 30. On a row's cross axis the viewport is stretched to the
/// host's height instead, and both authorities scroll.
///
/// `paddingTop` moves the scroller's viewport off the window's top edge, so
/// "masked to the viewport" and "masked to the window" are different rects.
@MainActor
private func renderInRowHost<E: Element>(_ element: E, _ w: Float, _ h: Float,
                                            _ authority: LayoutAuthority, table: StateTable,
                                            paddingTop: Float = 0) -> Frame {
    var host = Style()
    host.flexDirection = .row
    host.alignItems = .stretch
    host.size = sized(w, h).size
    host.padding = Edges(top: .pixels(px(paddingTop)), right: .pixels(px(0)),
                         bottom: .pixels(px(0)), left: .pixels(px(0)))
    let frame = authorityFrame(w, h, authority, table: table)
    var root = Box(style: host, content: element)
    frame.render(&root)
    return frame
}

/// A `deferred` block's fills carry a higher layer than an ordinary sibling's,
/// and that layer sorts AHEAD of emission order.
///
/// **Emission order is deliberately the opposite of the expected paint
/// order.** The deferred fill is emitted FIRST and the plain one SECOND: if
/// `deferred` did nothing to the layer, `Scene.finalize()`'s `(layer, order,
/// sequence)` sort would keep the emission order and this test would see
/// `[deferred, plain]`. Seeing `[plain, deferred]` instead is only possible
/// because the deferred fill's layer (1) sorts after the plain one's (0)
/// regardless of which was emitted first. Two siblings that happened to
/// share a layer would leave `finalize()` no signal but emission sequence,
/// so this test would pass whether or not `deferred` touched the layer at
/// all — giving the two genuinely different layers and reversing emission
/// order against paint order is what forces the layer mechanism itself to
/// be the thing under test.
///
/// **Not parameterised over the layout authority** (plan task 7 stage 5, `LR-CO`,
/// on `LR-BN`'s footing): this drives `PaintPass.deferred` on a bare `Frame` and never
/// lays anything out — no element, no layout and no authority in its call path,
/// so a `.proposal` arm would run the identical assertions and could never fail
/// differently from the `.legacy` one.
@Test @MainActor func aDeferredFillDrawsAfterAPlainSiblingEmittedLater() throws {
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    let deferredColor = Hsla(h: 0, s: 0, l: 1, a: 1)
    let plainColor = Hsla(h: 0, s: 0, l: 0, a: 1)
    pass.deferred {
        pass.fill(Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(10), height: px(10))),
                  color: deferredColor)
    }
    pass.fill(Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(10), height: px(10))),
              color: plainColor)

    let scene = frame.finalizedScene()
    try #require(scene.rects.count == 2)
    #expect(scene.rects[0].background.l == 0,
            "the plain fill (layer 0) draws first even though it was EMITTED second")
    #expect(scene.rects[1].background.l == 1,
            "the deferred fill (layer 1) draws last even though it was emitted first — a `deferred` that left the layer at 0 would keep emission order and reverse this")
}

/// A `deferred` block started from inside a REAL active clip is masked to the
/// whole surface, not to the ambient clip — the portal half of the mechanism.
///
/// **Started from inside `clipped(to:offsetBy:)`, not from a bare pass.** A
/// `deferred` block with no ancestor clip active would be masked to the whole
/// surface either way — "reset to the whole surface" and "no clip was ever
/// pushed" are the same answer there, so a `deferred` that does nothing to the
/// clip stack would still pass. Nesting inside a real 20×20 clip is what
/// forces the two apart: only a correct reset produces the full 300×300
/// mask instead of the pushed one.
///
/// **The offset is reset too, and this test checks that as well.** The
/// pushed clip carries a nonzero offset (`-40, -25`); a `deferred` that reset
/// only the clip bounds and left the offset accumulated would still
/// translate the fill by that amount, which is wrong for the same reason the
/// clip reset is: a modal must not slide with the scroll it is meant to
/// escape.
///
/// **Not parameterised over the layout authority** (plan task 7 stage 5, `LR-CO`,
/// on `LR-BN`'s footing): this drives `PaintPass.deferred` on a bare `Frame` and never
/// lays anything out — no element, no layout and no authority in its call path,
/// so a `.proposal` arm would run the identical assertions and could never fail
/// differently from the `.legacy` one.
@Test @MainActor func aDeferredFillInsideAnActiveClipEscapesToTheWholeSurface() throws {
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    pass.clipped(to: Bounds(origin: Point(x: px(10), y: px(10)),
                            size: Size(width: px(20), height: px(20))),
                 offsetBy: Point(x: px(-40), y: px(-25))) {
        pass.deferred {
            pass.fill(Bounds(origin: Point(x: px(5), y: px(5)),
                             size: Size(width: px(10), height: px(10))),
                      color: Hsla(h: 0, s: 0, l: 1, a: 1))
        }
    }

    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.contentMask.origin.x == 0, "the whole surface, not the pushed clip's origin (10)")
    #expect(r.contentMask.origin.y == 0)
    #expect(r.contentMask.size.width == 300, "the whole surface's width, not the pushed clip's (20)")
    #expect(r.contentMask.size.height == 300)
    #expect(r.bounds.origin.x == 5,
            "no accumulated offset applied — the raw fill origin, not 5 + (-40)")
    #expect(r.bounds.origin.y == 5, "not 5 + (-25)")
}

/// The layer AND the clip both pop when `deferred`'s block returns, restoring
/// exactly what was active before it — not the whole surface, and not layer 1.
///
/// **A `deferred` block that does not sit at the end of the scene.** A test
/// that only ever defers as the LAST thing painted cannot see a broken pop:
/// there would be nothing painted afterward to show the stale state. This one
/// pushes an ordinary clip, defers inside it, and then fills AGAIN inside the
/// same ordinary clip — so a `popClip`/`popLayer` that did nothing would leave
/// the second fill on the whole-surface mask and layer 1 instead of the
/// pushed clip and layer 0.
///
/// **`afterRect` is found by its own distinguishing size, not by sorted
/// index.** An earlier version of this test read `scene.rects[0]` and relied
/// on the layer sort having already put the "after" fill first — so under a
/// broken `popLayer` alone (the layer never restores, the clip does), the two
/// rects swap position in the SORTED array and `scene.rects[0]` silently
/// becomes the DEFERRED rect instead: the clip assertions below would then
/// fail because the wrong rect was inspected, not because the clip actually
/// leaked. Giving the two fills distinct sizes and looking `afterRect` up by
/// its own 6×6 makes the clip assertions test the clip alone.
///
/// **Not parameterised over the layout authority** (plan task 7 stage 5, `LR-CO`,
/// on `LR-BN`'s footing): this drives `PaintPass.deferred` on a bare `Frame` and never
/// lays anything out — no element, no layout and no authority in its call path,
/// so a `.proposal` arm would run the identical assertions and could never fail
/// differently from the `.legacy` one.
@Test @MainActor func deferredsLayerAndClipBothPopOnExit() throws {
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    let deferredColor = Hsla(h: 0, s: 0, l: 1, a: 1)
    let afterColor = Hsla(h: 0, s: 0, l: 0, a: 1)
    pass.clipped(to: Bounds(origin: Point(x: px(20), y: px(20)),
                            size: Size(width: px(40), height: px(40))),
                 offsetBy: Point(x: px(0), y: px(0))) {
        pass.deferred {
            pass.fill(Bounds(origin: Point(x: px(0), y: px(0)),
                             size: Size(width: px(5), height: px(5))),
                      color: deferredColor)
        }
        pass.fill(Bounds(origin: Point(x: px(0), y: px(0)),
                         size: Size(width: px(6), height: px(6))),
                  color: afterColor)
    }

    let scene = frame.finalizedScene()
    try #require(scene.rects.count == 2)
    let deferredRect = try #require(scene.rects.first { $0.bounds.size.width == 5 })
    let afterRect = try #require(scene.rects.first { $0.bounds.size.width == 6 })
    // Layer restored to 0: the "after" fill, emitted SECOND, draws FIRST —
    // exactly the reversal `aDeferredFillDrawsAfterAPlainSiblingEmittedLater`
    // proves for a fresh `deferred`, now proving the layer came back down.
    #expect(scene.rects.firstIndex(where: { $0.bounds.size.width == 6 }) == 0,
            "afterColor, restored to layer 0, draws first")
    #expect(scene.rects.firstIndex(where: { $0.bounds.size.width == 5 }) == 1,
            "deferredColor, stayed on layer 1, draws last")
    #expect(deferredRect.background.l == 1)
    #expect(afterRect.background.l == 0)
    // Clip restored to the pushed 40×40 mask, not the whole surface.
    #expect(afterRect.contentMask.origin.x == 20, "the outer clip's origin, not 0")
    #expect(afterRect.contentMask.size.width == 40, "the outer clip's width, not 300")
}

/// The prepaint half's own assertion: a scroll region registered from inside
/// `deferred` is recorded against the whole surface, not the ambient clip —
/// which is what makes hit-testing agree with where the paint half actually
/// draws.
///
/// **A paint-only test cannot see this.** `registerScrollRegion` writes to
/// `Frame.scrollRegions`, which nothing in the paint phase reads back; the
/// only way to see whether hoisting reached prepaint is to register something
/// from inside `PrepaintPass.deferred` and read the registry directly.
///
/// **Not parameterised over the layout authority** (plan task 7 stage 5, `LR-CO`,
/// on `LR-BN`'s footing): this drives `PrepaintPass.deferred` on a bare `Frame` and never
/// lays anything out — no element, no layout and no authority in its call path,
/// so a `.proposal` arm would run the identical assertions and could never fail
/// differently from the `.legacy` one.
@Test @MainActor func deferredOnPrepaintEscapesTheActiveClipForScrollRegistration() throws {
    let frame = Frame(contentSize: Size(width: px(300), height: px(300)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PrepaintPass(frame: frame)
    let narrowClip = Bounds(origin: Point(x: px(50), y: px(50)),
                            size: Size(width: px(20), height: px(20)))
    let wideRegion = Bounds(origin: Point(x: px(0), y: px(0)),
                            size: Size(width: px(300), height: px(300)))
    let id = GlobalElementID.child(of: nil, at: 0, name: nil)
    pass.clipped(to: narrowClip, offsetBy: Point(x: px(0), y: px(0))) {
        pass.deferred {
            pass.registerScrollRegion(wideRegion, id: id, axis: .vertical)
        }
    }

    let region = try #require(frame.scrollRegions.first)
    #expect(region.bounds == wideRegion,
            "intersected against the whole surface leaves it untouched — a broken clip reset would intersect it down to the narrow 20×20 clip instead")
}

/// `Deferred` must not collapse its content onto its own identity. `content`
/// gets its own derived child id — honouring `content`'s own `.id()` — the
/// same way `Box` derives one for ITS children, rather than sharing
/// `Deferred`'s own id outright.
///
/// **A differential against the known-correct shape, not a single hard-coded
/// path.** The same named `ScrollView` (named via its `elementID:`
/// parameter — it has no `StyledElement` modifier surface to reach `.id()`
/// through) is built at the same sibling position under `Deferred` and under
/// `Box`, and the two must resolve to the SAME `GlobalElementID`. A
/// `Deferred` that forwarded its own id straight to `content` (the bug this
/// pins) would still produce SOME id for the `ScrollView` — just a SHORTER
/// one, missing the `.named("list")` component entirely — so only comparing
/// against `Box`'s known-correct path catches it; asserting `idA` alone
/// against a hand-predicted value would not.
///
/// **Under both authorities, hosted** (plan task 7 stage 5 lane 2, `LR-CN`,
/// `LR-CO`): rendered through `LayoutDifferential.render` (`DifferentialRoot`, 100×50) rather than as the frame's root, because a
/// native root is centred at its own answer (`CN-J`, divergence 4, stage 6b's).
/// Every legacy literal here is the one it was unhosted — measured unchanged.
/// The proposal frame runs with diagnostics on and `try #require`s an empty
/// report before anything is read (`LR-BX`).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aNamedChildUnderDeferredResolvesTheSameAsUnderABox(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let frameA = LayoutDifferential.render(authority: authority, width: 100, height: 50) {
        Row {
            Deferred {
                ScrollView(.vertical, elementID: ElementID("list")) {
                    Box(style: sized(10, 200))
                }
            }
        }
    }
    try #require(frameA.unlowerableFields.isEmpty, "\(frameA.unlowerableFields)")
    let idA = try #require(frameA.scrollRegions.first).id

    let frameB = LayoutDifferential.render(authority: authority, width: 100, height: 50) {
        Row {
            Box {
                ScrollView(.vertical, elementID: ElementID("list")) {
                    Box(style: sized(10, 200))
                }
            }
        }
    }
    try #require(frameB.unlowerableFields.isEmpty, "\(frameB.unlowerableFields)")
    let idB = try #require(frameB.scrollRegions.first).id

    #expect(idA == idB,
            "same name at the same sibling position resolves to the same identity whether the ScrollView is wrapped by Deferred or by Box")
    guard case .named(let name) = idA.component else {
        Issue.record("expected the ScrollView's own id, .named(\"list\"), not Deferred's own positional one")
        return
    }
    #expect(name.name == "list")
}

/// `Deferred` is a single hoist, not a stack of stacking contexts — nesting
/// one inside another must not increment the layer, and both instances must
/// still balance independently on exit. `Frame.rootLayer`'s doc comment
/// states this property outright ("every instance — nested or not — lands on
/// the same layer"); this is what pins it.
///
/// **Not parameterised over the layout authority** (plan task 7 stage 5, `LR-CO`,
/// on `LR-BN`'s footing): this drives `PaintPass.deferred` on a bare `Frame` and never
/// lays anything out — no element, no layout and no authority in its call path,
/// so a `.proposal` arm would run the identical assertions and could never fail
/// differently from the `.legacy` one.
@Test @MainActor func nestedDeferredsAllLandOnTheSameRootLayer() throws {
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    let pass = PaintPass(frame: frame)
    #expect(frame.activeLayer == 0)
    pass.deferred {
        #expect(frame.activeLayer == 1)
        pass.deferred {
            #expect(frame.activeLayer == 1,
                    "a nested deferred lands on the SAME root layer, not layer 2 — one hoist, not a stack of stacking contexts")
        }
        #expect(frame.activeLayer == 1, "back to the outer deferred's layer once the inner one pops")
    }
    #expect(frame.activeLayer == 0, "back to ordinary paint order once both pop")
}

/// The `Deferred` element itself, not just `pass.deferred` — proves the
/// wiring in `Deferred.swift` reaches both phases through a real element
/// tree, and that it introduces no layout node of its own (both boxes keep
/// their declared sizes).
///
/// Mirrors the first test's shape: the `Deferred`-wrapped box is declared
/// (and therefore emitted) FIRST, the plain sibling second, and only a
/// correct hoist reverses that into paint order.
///
/// **Under both authorities, hosted** (plan task 7 stage 5 lane 2, `LR-CN`,
/// `LR-CO`): rendered through `LayoutDifferential.render` (`DifferentialRoot`, 200×200) rather than as the frame's root, because a
/// native root is centred at its own answer (`CN-J`, divergence 4, stage 6b's).
/// Every legacy literal here is the one it was unhosted — measured unchanged.
/// The proposal frame runs with diagnostics on and `try #require`s an empty
/// report before anything is read (`LR-BX`).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aDeferredElementHoistsItsChildAboveASiblingDeclaredAfterIt(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let frame = LayoutDifferential.render(authority: authority, width: 200, height: 200) {
        Row {
            Deferred {
                Box(style: sized(30, 30)).background(.accent)
            }
            Box(style: sized(40, 40)).background(.surface)
        }
    }
    try #require(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")

    let scene = frame.finalizedScene()
    try #require(scene.rects.count == 2)
    #expect(scene.rects[0].bounds.size.width == 40,
            "the plain 40-wide sibling draws first, on the ordinary layer")
    #expect(scene.rects[1].bounds.size.width == 30,
            "the deferred 30-wide box draws last, hoisted, even though it was declared first")
}

/// The element-level prepaint wiring, guarded — not just `PrepaintPass.deferred`
/// itself (already covered above), but that `Deferred.prepaint` actually
/// CALLS it. A version of `Deferred.prepaint` that called `content.prepaint`
/// directly, skipping `pass.deferred`, still compiles and links (the symbol
/// is referenced elsewhere on `PrepaintPass`), and no paint-only assertion
/// can see the difference — the scroll-region registry is prepaint state
/// that nothing in `paint` reads back.
///
/// **The composition that tells them apart: `ScrollView.prepaint` registers
/// ITS OWN region OUTSIDE its own clip, but its CHILDREN register INSIDE
/// it.** So an inner `ScrollView` wrapped in `Deferred`, nested inside an
/// outer one, is exactly the shape where a broken hoist is visible: the
/// inner's region is a CHILD of the outer's clipped subtree, and only
/// `Deferred` resetting that clip before descending keeps the inner's own
/// raw geometry intact. This is precisely the hit-testing failure that put
/// `deferred` on `PrepaintPass` in the first place — a tooltip escaping the
/// clip visually while still being hit-tested as if it hadn't.
///
/// **The outer ScrollView is genuinely narrower than the frame — not the
/// synthetic-clip-uniformity hazard.** `Column(alignItems: .stretch).width(50)`
/// wrapping a `.horizontal` `ScrollView` binds the outer's own WIDTH to 50pt
/// via ordinary cross-axis stretch (verified: the outer's own registered
/// region is 50pt wide, not the 300pt frame). The inner `ScrollView` sits
/// inside the outer's horizontally-scrolling content, wrapped in its own
/// `Column(alignItems: .stretch).width(150)` to give it an explicit width
/// wider than the outer's 50pt viewport (verified against the oracle
/// probe: the inner's raw region is 150pt wide, positioned at x=30, so
/// intersecting it with the outer's 50pt clip (x 0...50) would crop it to
/// 20pt — intersecting it with the frame's whole 300pt surface leaves it at
/// its full 150).
///
/// **Under both authorities, hosted** (plan task 7 stage 5 lane 2, `LR-CN`,
/// `LR-CO`): rendered through `LayoutDifferential.render` (`DifferentialRoot`, 300×300) rather than as the frame's root, because a
/// native root is centred at its own answer (`CN-J`, divergence 4, stage 6b's).
/// Every legacy literal here is the one it was unhosted — measured unchanged.
/// The proposal frame runs with diagnostics on and `try #require`s an empty
/// report before anything is read (`LR-BX`).
///
/// Measured red before hosting (stage 5 lane 2's red-first commit): under
/// `.proposal` as the frame's root the inner region read x 155, width 145, and the
/// outer x 125 — the root centred, not the hoist broken.
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    let frame = LayoutDifferential.render(authority: authority, width: 300, height: 300) {
        Column {
            ScrollView(.horizontal, elementID: ElementID("outer")) {
                Box(style: sized(30, 20))
                Deferred {
                    Column {
                        ScrollView(.vertical, elementID: ElementID("inner")) {
                            Box(style: sized(20, 20))
                        }
                    }
                    .cssWidth(px(150))
                    .alignItems(.stretch)
                }
            }
        }
        .cssWidth(px(50))
        .alignItems(.stretch)
    }
    try #require(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")

    let outer = try #require(frame.scrollRegions.first { $0.axis == .horizontal })
    let inner = try #require(frame.scrollRegions.first { $0.axis == .vertical })

    #expect(outer.bounds.size.width == 50,
            "the outer ScrollView's own registered region confirms its clip is genuinely narrower than the 300pt frame")
    #expect(inner.bounds.origin.x == 30 && inner.bounds.size.width == 150,
            "the inner ScrollView's region survives at its own RAW geometry — a broken hoist would intersect it down to (30, 0, 20, 20), cropped to the outer's 50pt clip")
}

/// The "one more": `Deferred` composed with a REAL, live-scrolled
/// `ScrollView` — not a synthetic `pass.clipped` push. Every other clip in
/// this file is synthetic; this is the motivating composition itself, a
/// modal-shaped box inside a scroller that must not slide with the content
/// around it.
///
/// **Two renders sharing one `StateTable`, exactly the way scroll position
/// survives across frames in production** (`Window` hands every `Frame` the
/// same table). The first render is unscrolled and just reads back each
/// marker's RAW position; a real offset is then written into the SAME table
/// under the `ScrollView`'s own registered id, and the second render reads
/// the SAME markers back scrolled.
///
/// **The differential, not a hard-coded number.** The ORDINARY marker
/// (21pt wide) is expected to shift by exactly `-offset` — asserting that
/// first is what proves the seeded offset really reached paint, rather than
/// the test silently passing because nothing scrolled at all. Only against
/// that baseline does "the deferred marker (22pt wide) does not move"
/// mean anything: it is the escape from the SAME scroll that just moved its
/// sibling, not merely the absence of movement in a test that scrolled
/// nothing.
///
/// **Under both authorities, hosted** (plan task 7 stage 5 lane 2, `LR-CN`,
/// `LR-CO`): rendered through `renderInRowHost` (a 100×60 row `Box` over one `StateTable`) rather than as the frame's root, because a
/// native root is centred at its own answer (`CN-J`, divergence 4, stage 6b's).
/// Every legacy literal here is the one it was unhosted — measured unchanged.
/// The proposal frame runs with diagnostics on and `try #require`s an empty
/// report before anything is read (`LR-BX`).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll(_ authority: LayoutAuthority) throws {
    AuthorityCoverage.record(#function, authority)
    func makeTree() -> some Element {
        ScrollView(.vertical, elementID: ElementID("outer")) {
            Box(style: sized(20, 300))                        // filler: forces real overflow
            Box(style: sized(21, 20)).background(.accent)      // ordinary marker
            Deferred {
                Box(style: sized(22, 20)).background(.accent)  // deferred marker
            }
        }
    }

    let stateTable = StateTable()

    let frame1 = renderInRowHost(makeTree(), 100, 60, authority, table: stateTable)
    try #require(frame1.unlowerableFields.isEmpty, "\(frame1.unlowerableFields)")
    let scene1 = frame1.finalizedScene()
    let ordinaryRaw = try #require(scene1.rects.first { $0.bounds.size.width == 21 })
    let deferredRaw = try #require(scene1.rects.first { $0.bounds.size.width == 22 })

    let outerID = try #require(frame1.scrollRegions.first).id
    stateTable.withState(outerID, initial: ScrollState()) { $0.offset = 40 }

    let frame2 = renderInRowHost(makeTree(), 100, 60, authority, table: stateTable)
    try #require(frame2.unlowerableFields.isEmpty, "\(frame2.unlowerableFields)")
    let scene2 = frame2.finalizedScene()
    let ordinaryScrolled = try #require(scene2.rects.first { $0.bounds.size.width == 21 })
    let deferredScrolled = try #require(scene2.rects.first { $0.bounds.size.width == 22 })

    #expect(ordinaryScrolled.bounds.origin.y == ordinaryRaw.bounds.origin.y - 40,
            "an ordinary sibling tracks the scroll -- confirms the seeded offset really reached paint")
    #expect(deferredScrolled.bounds.origin.y == deferredRaw.bounds.origin.y,
            "the deferred box stays at its RAW position -- it escapes the scroll translation, not merely the clip")
}

// MARK: - Stage 5, lane 2 (`LR-CN`, `LR-CO`): the demo's scrim under both authorities

/// **2.5** (plan task 7 stage 5, `LR-CH`/`LR-CI`, `AP-I`). The demo modal's
/// shape — `ScrollView { Deferred { Stack { card }.position(.absolute).inset(0)
/// .background(.scrim).onClick {} }; tall content }` — under **both** authorities,
/// over two frames sharing one `StateTable`, the second scrolled 40.
///
/// Under the legacy authority the scrim's `inset(0)` makes it the root's padding
/// box, which is the window; under the proposal one the pair is a presentation
/// root laid out against the window. Either way, on **both** frames:
///
/// - the scrim's rect and its mask are the window (200×100) — not the viewport,
///   which starts 30 down (the host's top padding), so a portal that stopped
///   resetting the clip reads a different mask, and one that stopped resetting
///   the translation reads y −40 on the second frame;
/// - it draws after the in-flow marker although it is declared, and emitted,
///   first — layer 1;
/// - its hitbox is the topmost opaque one outside the card, at the window rect,
///   on layer 1, and it is not a scroll region;
/// - the card is centred, (80, 35) 40×30, and is the topmost opaque hitbox at the
///   window's centre;
/// - the in-flow marker moved by exactly the offset, which is what says the
///   offset reached paint at all.
///
/// Pre-flighted under diagnostics: the proposal frame's report must be empty
/// before anything is read (`LR-BX`).
@Test(arguments: AuthorityCoverage.authorities) @MainActor
func aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities(
    _ authority: LayoutAuthority
) throws {
    AuthorityCoverage.record(#function, authority)
    func makeTree() -> some Element {
        ScrollView(.vertical, elementID: ElementID("list")) {
            Deferred {
                Stack(alignment: .center) {
                    Box(style: sized(40, 30)).background(.surface).onClick {}
                }
                .position(.absolute)
                .inset(px(0))
                .background(.scrim)
                .onClick {}
            }
            Box(style: sized(21, 300)).background(.accent)   // in-flow marker
        }
    }
    let window = Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(200), height: px(100)))
    let card = Bounds(origin: Point(x: px(80), y: px(35)), size: Size(width: px(40), height: px(30)))
    let table = StateTable()

    func check(_ frame: Frame, markerY: Float, _ label: String) throws {
        try #require(frame.unlowerableFields.isEmpty, "\(label): \(frame.unlowerableFields)")
        let scene = frame.finalizedScene()
        let scrimIndex = try #require(scene.rects.firstIndex { $0.bounds.size.width == 200 && $0.bounds.size.height == 100 },
                                      "\(label): no window-sized scrim rect")
        let markerIndex = try #require(scene.rects.firstIndex { $0.bounds.size.width == 21 })
        let scrim = scene.rects[scrimIndex]
        #expect(Bounds(origin: Point(x: px(scrim.bounds.origin.x), y: px(scrim.bounds.origin.y)),
                       size: Size(width: px(scrim.bounds.size.width), height: px(scrim.bounds.size.height))) == window,
                "\(label): the scrim is the window")
        #expect(scrim.contentMask.origin.x == 0 && scrim.contentMask.origin.y == 0
                    && scrim.contentMask.size.width == 200 && scrim.contentMask.size.height == 100,
                "\(label): masked to the window, not the viewport at y 30")
        #expect(scrimIndex > markerIndex,
                "\(label): the scrim, declared and emitted first, draws after the marker — layer 1")
        let cardRect = try #require(scene.rects.first { $0.bounds.size.width == 40 && $0.bounds.size.height == 30 })
        #expect(cardRect.bounds.origin.x == 80 && cardRect.bounds.origin.y == 35, "\(label): the card is centred")
        #expect(scene.rects[markerIndex].bounds.origin.y == markerY, "\(label): the in-flow marker")

        let outside = try #require(topmostOpaqueHitbox(in: frame.hitboxes, at: Point(x: px(10), y: px(50))))
        let scrimHit = frame.hitboxes[outside]
        #expect(scrimHit.bounds == window && scrimHit.layer == 1 && scrimHit.scroll == nil,
                "\(label): outside the card the topmost opaque hitbox is the scrim's, at the window, on layer 1")
        let centre = try #require(topmostOpaqueHitbox(in: frame.hitboxes, at: Point(x: px(100), y: px(50))))
        #expect(frame.hitboxes[centre].bounds == card && frame.hitboxes[centre].layer == 1,
                "\(label): the card's hitbox wins at the centre")
    }

    let first = renderInRowHost(makeTree(), 200, 100, authority, table: table, paddingTop: 30)
    try check(first, markerY: 30, "unscrolled")
    let listID = try #require(first.scrollRegions.first).id
    table.withState(listID, initial: ScrollState()) { $0.offset = 40 }
    let second = renderInRowHost(makeTree(), 200, 100, authority, table: table, paddingTop: 30)
    try check(second, markerY: -10, "scrolled 40")
}
