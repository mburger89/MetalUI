import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender
@testable import MetalUI

// Lane 1 of plan task 5 (`docs/superpowers/specs/2026-09-15-outer-modifiers-design.md`).
// **The audit, pinned as it stands.** No `Sources/` change belongs with this
// file: every assertion below is a reading of the tree at `c4b5853`, so that
// lanes 2–4 move numbers a test already watches rather than numbers nobody
// wrote down.
//
// Two things live here.
//
// 1. `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` — the
//    spec's §3 matrix as a table. Each row names a modifier, the path it is
//    written on, and the KINDS it is claimed to be; the test measures two arms
//    that differ only by that modifier and asserts each claimed kind against
//    its own mechanism-specific witness (ruling OM-X).
// 2. Four order tests, each expectation taken from an arm of
//    `docs/probes/swiftui-outer-modifier-order.swift`,
//    `swiftui-border-clip-paint.swift` or `swiftui-content-shape-hit-region.swift`.
//    Two of them pin MetalUI's answer where it disagrees with SwiftUI's, on
//    purpose and by name.
//
// **Why the kind is not read off one tuple** (ruling OM-X, design review round
// 2). A triple of `(nodeDelta, outerSizeDelta, rectDelta)` cannot tell "self",
// "prepaint-only" and "genuinely inert" apart — all three read `(0, 0, 0)` —
// and `hidden()`, which moves layout without adding a node, would classify as
// "wraps" under a witness that only asked whether the outer size moved. The
// row that made this concrete was `borderWidth(_:) on a sized box`: it was the
// API this whole audit existed to expose, and on the five-tuple it moved
// **nothing at all**, so its two arms were separated only by the storage
// witness. That is why the storage comparison is part of the instrument rather
// than a convenience. Lane 2 deleted the modifier (`OM-M`) and its two rows are
// now `border(_:width:)` rows reading `selfStorage + paintOnly`; `id(_:)`
// carries the storage-witness-only case on its own.
//
// **What "the arms disagree" means here, and when it is checked.** A row whose
// two arms measure identically in all five tuple components AND in storage is
// a broken instrument, not an inert modifier, and it fails as one — the
// `#require` runs BEFORE any kind is derived, not merely before two row values
// are compared (taxonomy shape 15 read through the spec's §7).

// MARK: - Harness

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// A failure message assembled from pieces. `Comment` is
/// `ExpressibleByStringInterpolation`, so a single literal converts on its own,
/// but a `+` concatenation of two literals is a `String` and does not — this is
/// the one-character bridge.
private func why(_ message: String) -> Comment { "\(message)" }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> {
    Point(x: Pixels(x), y: Pixels(y))
}

/// Counts the clicks a fixture's `onClick` actually ran. A class because the
/// element that captures it is a value copied through three phases.
@MainActor
private final class ClickCounter {
    var count = 0
    func bump() { count += 1 }
}

/// Every field of an emitted rect that any modifier in the matrix could move,
/// rendered as one string so two arms compare as lists.
///
/// **`contentMask`, `borderColor` and `borderWidths` are in here deliberately.**
/// Without the mask a `.clipped()` would read as "paints nothing new"; without
/// the two border fields, `border(_:width:)`'s two rows would have nothing to
/// see at all — a paint-only border changes no bounds, no colour and no radius,
/// only those two fields.
private func describe(_ r: MUIRect) -> String {
    let b = r.bounds
    let m = r.contentMask
    let c = r.cornerRadii
    let w = r.borderWidths
    return "[\(b.origin.x) \(b.origin.y) \(b.size.width)x\(b.size.height)]"
        + " bg(\(r.background.h),\(r.background.s),\(r.background.l),\(r.background.a))"
        + " radii(\(c.topLeft),\(c.topRight),\(c.bottomRight),\(c.bottomLeft))"
        + " border(\(w.top),\(w.right),\(w.bottom),\(w.left))"
        + " borderColor(\(r.borderColor.h),\(r.borderColor.s),\(r.borderColor.l),\(r.borderColor.a))"
        + " mask[\(m.origin.x) \(m.origin.y) \(m.size.width)x\(m.size.height)]"
}

/// A registered hit region, **without its owning id**.
///
/// The id is left out on purpose: `.id(_:)` renames every `GlobalElementID`
/// under it, and a fingerprint that carried the id would report a moved hit
/// REGION for a modifier that moved nothing but a name — which is the
/// misclassification this instrument exists to avoid. What a hit region is, is
/// where it is and whether it consumes the point.
private func describe(_ h: Hitbox) -> String {
    let b = h.bounds
    return "[\(b.origin.x.value) \(b.origin.y.value) \(b.size.width.value)x\(b.size.height.value)]"
        + " opaque=\(h.opaque) layer=\(h.layer) scroll=\(String(describing: h.scroll))"
}

/// What the `Handlers` of one arm look like. `Handlers` is not `Equatable`
/// (it holds closures), so the storage witness compares this projection —
/// the same shape `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` uses,
/// and it must gain a member in the same change `Handlers` does.
private struct HandlerFingerprint: Equatable {
    var click = false
    var key = false
    var focusable = false
    var actionCount = 0
    var context: KeyContext?
    var axNode = AXNode()
    /// Plan task 5's lane 3 — the two hit-testing members.
    var allowsHitTesting = true
    var contentShapeInset: Edges<Pixels>?
    /// Roadmap item 14 (TI-B).
    var textInput = false

    @MainActor init(_ h: Handlers) {
        click = h.onClick != nil
        key = h.onKey != nil
        focusable = h.isFocusable
        actionCount = h.actions.count
        context = h.keyContext
        axNode = h.axNode
        allowsHitTesting = h.allowsHitTesting
        contentShapeInset = h.contentShapeInset
        textInput = h.textInput != nil
    }
}

/// Whether the two arms' **outermost** stored state differs.
///
/// Generic over `StyledElement`, which is what makes it the same question for a
/// bare `Box` and for a `ModifiedElement` chain: the chain's four accessors read
/// and write `outermost`, so this compares the layer a `Self`-returning modifier
/// configures (ruling MC-A, seen from the caller's side).
@MainActor
private func storageDiffers<A: StyledElement, B: StyledElement>(_ a: A, _ b: B) -> Bool {
    a.style != b.style
        || a.decoration != b.decoration
        || a.elementID != b.elementID
        || HandlerFingerprint(a.handlers) != HandlerFingerprint(b.handlers)
}

/// The five-tuple one arm produces, plus the rect and hit-region lists the
/// deltas are computed from.
private struct Observation: Equatable {
    /// `LayoutTree.nodeCount` for the whole fixture.
    var nodeCount: Int
    /// The x of the 1x1 marker declared after the subject: the subject's outer
    /// width, measured the way record §15's scratch arms measured it.
    var outerWidth: Float
    /// Every emitted rect but the marker's.
    var rects: [String]
    /// The same rects' SIZES alone, in the same order.
    ///
    /// **The `distributes` witness reads this and not `rects`, and the reason
    /// was found by mutation.** A component's members sit in one flex line, so
    /// growing member 0 pushes member 1 sideways: with the whole rect compared,
    /// an amend that reached only the FIRST member still moved the second one's
    /// string, and `StyledComponent.requestGroupLayout` amending
    /// `nodes.prefix(1)` reddened nothing. A member's size is what the modifier
    /// did to it; its position is what its siblings did to it.
    var rectSizes: [String]
    /// Every registered hit region.
    var hitRegions: [String]
    /// How many `onClick` closures a synthesized down/up pair at the row's
    /// probe point actually ran.
    var hitCountAtEdge: Int
}

/// Renders one arm and reads all five components off it.
///
/// **Through a real `Window` for four of the five, and through a directly built
/// `Frame` for the node count.** `Window` does not retain its `Frame` (it keeps
/// `lastScene`, `lastHitboxes` and `lastFocusRegistry` and lets the frame go),
/// and `LayoutTree.nodeCount` is the only spelling of "did this modifier add a
/// node" the repo has — `frame.tree.nodeCount`, the same idiom
/// `ElementLayoutTests` and `ComponentTests` already use. So the same root is
/// built a second time at the same content size and rendered through a bare
/// `Frame`. The two renders see the same element values; nothing in the four
/// window-side readings depends on the node count and vice versa.
///
/// The fixture is `Row { subject; marker }.alignItems(.flexStart)`. The
/// `alignItems` is load-bearing: `Row` centres on the cross axis (EP-8), so
/// without it a cross-axis size is the container's answer rather than the
/// modifier's — record §15's A1 arm read a 200-tall fill for exactly that
/// reason.
@MainActor
private func observe<Subject: ElementGroup>(
    windowSize: Int = 200,
    probe: Point<Pixels>,
    interact: @MainActor (Window, FakePlatformWindow) -> Void = { _, _ in },
    subject: @escaping @MainActor (ClickCounter) -> Subject
) throws -> Observation {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let counter = ClickCounter()
    // P-CSS, owner 7b (stage 6b, `LR-DI`): the matrix's only caller reads the
    // legacy tree's node shape (CSS-structure), so both renders here — the
    // window and the node-count `Frame` — stay on `.legacy`.
    let (window, platform) = try makeFakeWindow(device: device, size: windowSize,
                                                layoutAuthority: .legacy) {
        Row {
            subject(counter)
            Box().width(px(1)).height(px(1)).background(.separator)
        }.alignItems(.flexStart)
    }
    window.drawFrameIfNeeded()
    interact(window, platform)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()

    let scene = window.lastScene
    let isMarker: (MUIRect) -> Bool = { $0.bounds.size.width == 1 && $0.bounds.size.height == 1 }
    let marker = try #require(scene.rects.first(where: isMarker),
                              "the 1x1 marker painted no rect — the fixture never reached paint")
    let hitRegions = window.lastHitboxes.map(describe)

    platform.simulateInput(.mouseDown(MouseEvent(position: probe)))
    platform.simulateInput(.mouseUp(MouseEvent(position: probe)))

    let sink = ClickCounter()
    var tree = Row {
        subject(sink)
        Box().width(px(1)).height(px(1)).background(.separator)
    }.alignItems(.flexStart)
    let frame = Frame(contentSize: Size(width: px(Float(windowSize)), height: px(Float(windowSize))),
                      scaleFactor: 1, layoutAuthority: .legacy)
    frame.render(&tree)

    let subjectRects = scene.rects.filter { !isMarker($0) }
    return Observation(nodeCount: frame.tree.nodeCount,
                       outerWidth: marker.bounds.origin.x,
                       rects: subjectRects.map(describe),
                       rectSizes: subjectRects.map { "\($0.bounds.size.width)x\($0.bounds.size.height)" },
                       hitRegions: hitRegions,
                       hitCountAtEdge: counter.count)
}

// MARK: - The matrix

/// One cell of the spec's §3.1 table, as a claim the test can refute.
private enum Kind: String, CaseIterable, Hashable {
    /// Adds a layout node around the receiver.
    case wraps
    /// Writes the receiver's own `Style`/`Decoration`/`Handlers`/`ElementID` —
    /// on a chain, the OUTERMOST layer's.
    case selfStorage
    /// Changes what is emitted, and moves nothing the engine produced.
    case paintOnly
    /// Changes what is registered for hit testing, and emits nothing.
    case prepaintOnly
    /// Applied to each of a `Component`'s top-level nodes.
    case distributes
}

@MainActor
private struct MatrixRow {
    let name: String
    let path: String
    let kinds: Set<Kind>
    /// What the row is here to say beyond its kinds — quoted in failures.
    let note: String
    /// How many top-level nodes a `.distributes` row's component has. `nil` for
    /// every other row.
    var memberCount: Int?
    /// The two arms and, where the comparison is meaningful, whether their
    /// outermost stored state differs. `nil` where it is not: a wrapping
    /// modifier returns a different TYPE, so "did the receiver's own storage
    /// change" is not a question about it.
    let arms: @MainActor () throws -> (bare: Observation, declared: Observation, storage: Bool?)
}

/// A two-member component, for the `distributes` rows.
///
/// The members disagree in both dimensions (30x10 and 50x20) so that a
/// modifier applied once around the pair, rather than once per member, moves a
/// different set of numbers than one applied to each — the shape `TwoLeaves`
/// in `ComponentTests.swift` records having found the hard way.
private struct TwoMembers: Component {
    var content: some ElementGroup {
        Box().width(px(30)).height(px(10)).background(.accent)
        Box().width(px(50)).height(px(20)).background(.surface)
    }
}

/// Every outer modifier the legacy path offers today is the kind the matrix
/// says it is, and each kind is proved by its own mechanism.
///
/// **The rows are the audit.** A modifier filed under the wrong kind is a
/// documentation artefact wearing a test's name, so each kind has a witness
/// that a *different* kind cannot satisfy, and each row also carries the
/// NEGATIVE of the kinds it does not claim:
///
/// | kind | witness |
/// |---|---|
/// | `wraps` | `nodeDelta > 0` **and** `outerSizeDelta > 0` |
/// | `selfStorage` | `nodeDelta == 0` **and** the outermost layer's stored state differs |
/// | `paintOnly` | `nodeDelta == 0 && outerSizeDelta == 0` **and** the emitted rects differ |
/// | `prepaintOnly` | the first three all zero **and** the hit regions or the click count move |
/// | `distributes` | each of the component's `memberCount` members' own SIZE changed (an amend, `OM-AD`); with `wraps` also claimed, exactly one node per member and each member's own size UNCHANGED — a wrap per member (`OM-AM`, lane 4's `padding`) |
///
/// and, for every row: a row that does not claim `wraps` must add no node; a
/// row that claims neither `paintOnly` nor `distributes` must emit **byte-
/// identical** rects; a row that does not claim `prepaintOnly` must leave the
/// hit regions and the click count exactly where they were.
///
/// The last two negatives are what make the two `border(_:width:)` rows a
/// finding rather than a formality. The sized-box subject carries a background
/// in both arms, so "the rects differ" is a statement about a live rect's
/// `borderWidths` and `borderColor` fields — not the vacuous truth it would be
/// if a rect had simply appeared from nothing — and the content-sized one's
/// `does not claim wraps` negative is what states that a paint-only border,
/// unlike the deleted `borderWidth(_:)`, moves no layout at all.
@Test @MainActor func everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays() throws {
    let rows: [MatrixRow] = [
        // MARK: wraps
        MatrixRow(name: "padding(_:)", path: "legacy Element", kinds: [.wraps],
                  note: "one ModifierLayer per call (MC-A)",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in Box().width(px(40)).height(px(40)) },
                       try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(40)).height(px(40)).padding(px(8))
                       },
                       nil)
                  }),
        MatrixRow(name: "frame(width:height:)", path: "legacy Element", kinds: [.wraps],
                  note: "a centred ModifierLayer that does not overwrite the content's own size",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in Box().width(px(20)).height(px(20)) },
                       try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(20)).height(px(20)).frame(width: px(60), height: px(60))
                       },
                       nil)
                  }),

        // MARK: self, and the layout engine reads it
        MatrixRow(name: "width(_:)", path: "legacy Element", kinds: [.selfStorage],
                  note: "writes Style.size.width on the receiver's own node",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in Box().height(px(40)) },
                       try observe(probe: pt(2, 2)) { _ in Box().height(px(40)).width(px(40)) },
                       storageDiffers(Box().height(px(40)),
                                      Box().height(px(40)).width(px(40))))
                  }),
        MatrixRow(name: "margin(_:)", path: "legacy Element", kinds: [.selfStorage],
                  note: "writes Style.margin; outside the box, so the marker moves by twice it",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in Box().width(px(20)).height(px(20)) },
                       try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(20)).height(px(20)).margin(px(10))
                       },
                       storageDiffers(Box().width(px(20)).height(px(20)),
                                      Box().width(px(20)).height(px(20)).margin(px(10))))
                  }),
        MatrixRow(name: "hidden()", path: "legacy Element", kinds: [.selfStorage],
                  note: "writes Style.display = .none — layout filters it and it adds NO node, "
                      + "which is what separates it from `wraps` under this instrument",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in Box().width(px(20)).height(px(20)) },
                       try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(20)).height(px(20)).hidden()
                       },
                       storageDiffers(Box().width(px(20)).height(px(20)),
                                      Box().width(px(20)).height(px(20)).hidden()))
                  }),
        MatrixRow(name: "id(_:)", path: "legacy Element", kinds: [.selfStorage],
                  note: "writes elementID and NOTHING the five-tuple can see — the row that "
                      + "makes the storage witness necessary rather than decorative",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in Box().width(px(40)).height(px(40)) },
                       try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(40)).height(px(40)).id("beacon")
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)),
                                      Box().width(px(40)).height(px(40)).id("beacon")))
                  }),
        MatrixRow(name: "focusable()", path: "legacy Element", kinds: [.selfStorage],
                  note: "writes Handlers.isFocusable and registers NO pointer target — the "
                      + "keyboard gate is separate from `onClick`'s and must stay so",
                  arms: {
                      (try observe(probe: pt(20, 20)) { _ in Box().width(px(40)).height(px(40)) },
                       try observe(probe: pt(20, 20)) { _ in
                           Box().width(px(40)).height(px(40)).focusable()
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)),
                                      Box().width(px(40)).height(px(40)).focusable()))
                  }),

        // MARK: what the inert one BECAME (lane 2, rulings OM-B and OM-M)
        //
        // These two rows replace `borderWidth(_:) on a sized box` and
        // `borderWidth(_:) on a content-sized box`, which lane 1 measured as
        // `selfStorage / node 0 / outer 0 / rects identical` and
        // `selfStorage / node 0 / outer +8 / rects identical` — the standing
        // inert row of CLAUDE.md's declared-but-inert table, and the API this
        // audit existed to expose. `border(_:width:)` reads `selfStorage +
        // paintOnly` on BOTH shapes: the emitted rect's `borderWidths` and
        // `borderColor` move, and the content-sized box's **outer size no
        // longer does**, which is the `OM-B` half of the finding (SwiftUI's
        // `.border` is layout-neutral, probe arm L2) as opposed to the `OM-M`
        // half (it paints at all).
        MatrixRow(name: "border(_:width:) on a sized box", path: "legacy Element",
                  kinds: [.selfStorage, .paintOnly],
                  note: "the replacement for the deleted borderWidth(_:): it paints, and the "
                      + "rect that moves is a LIVE one — the subject carries a background in "
                      + "both arms, so `the rects differ` is about borderWidths and borderColor "
                      + "rather than about a rect appearing from nothing",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(40)).height(px(40)).background(.accent)
                       },
                       try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(40)).height(px(40)).background(.accent)
                               .border(.separator, width: px(4))
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)).background(.accent),
                                      Box().width(px(40)).height(px(40)).background(.accent)
                                          .border(.separator, width: px(4))))
                  }),
        MatrixRow(name: "border(_:width:) on a content-sized box", path: "legacy Element",
                  kinds: [.selfStorage, .paintOnly],
                  note: "the other half: where borderWidth(_:) moved this same box by +8 and "
                      + "still painted nothing, a paint-only border moves NOTHING and paints. "
                      + "The `does not claim wraps` negative below is what states the first "
                      + "half, and the paintOnly witness the second",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in
                           Box { Box().width(px(30)).height(px(10)) }
                       },
                       try observe(probe: pt(2, 2)) { _ in
                           Box { Box().width(px(30)).height(px(10)) }
                               .border(.separator, width: px(4))
                       },
                       storageDiffers(Box { Box().width(px(30)).height(px(10)) },
                                      Box { Box().width(px(30)).height(px(10)) }
                                          .border(.separator, width: px(4))))
                  }),
        MatrixRow(name: "focusBorder(_:width:), genuinely focused", path: "legacy Element",
                  kinds: [.selfStorage, .paintOnly],
                  note: "THE FOCUS RING (OM-L). The subject is focused in both arms, so what "
                      + "differs is the declaration and not the state — the shape "
                      + "`hoverBackground(_:), genuinely hovered` above uses, one chain over",
                  arms: {
                      let focus: @MainActor (Window, FakePlatformWindow) -> Void = { window, _ in
                          if let first = window.lastHitboxes.first { window.focus(first.id) }
                      }
                      return (try observe(probe: pt(2, 2), interact: focus) { counter in
                                  Box().width(px(40)).height(px(40)).background(.surface)
                                      .focusable().onClick { counter.bump() }
                              },
                              try observe(probe: pt(2, 2), interact: focus) { counter in
                                  Box().width(px(40)).height(px(40)).background(.surface)
                                      .focusBorder(.accent, width: px(2))
                                      .focusable().onClick { counter.bump() }
                              },
                              storageDiffers(Box().width(px(40)).height(px(40)).background(.surface),
                                             Box().width(px(40)).height(px(40)).background(.surface)
                                                 .focusBorder(.accent, width: px(2))))
                  }),
        MatrixRow(name: "opacity(_:)", path: "legacy Element",
                  kinds: [.selfStorage, .paintOnly],
                  note: "a paint-phase SCOPE, not an emission: the subject's own fill fades "
                      + "(OM-N), and no number the engine produced moves",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(40)).height(px(40)).background(.accent)
                       },
                       try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(40)).height(px(40)).background(.accent).opacity(0.5)
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)).background(.accent),
                                      Box().width(px(40)).height(px(40)).background(.accent)
                                          .opacity(0.5)))
                  }),
        MatrixRow(name: "clipped()", path: "legacy Element",
                  kinds: [.selfStorage, .paintOnly],
                  note: "also a scope. The CHILD's rect is what moves — its contentMask stops "
                      + "being the whole surface — so the subject needs a child that overflows "
                      + "it, with flexShrink(0) or the engine shrinks the child to fit and "
                      + "nothing is clipped. Its PREPAINT half cannot be claimed here: this "
                      + "instrument treats prepaint-only and paint-only as exclusive, and "
                      + "`clippedAlsoClipsTheHitboxesInsideIt` pins it instead",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in
                           Box { Box().width(px(60)).height(px(60)).flexShrink(0).background(.surface) }
                               .width(px(40)).height(px(40))
                       },
                       try observe(probe: pt(2, 2)) { _ in
                           Box { Box().width(px(60)).height(px(60)).flexShrink(0).background(.surface) }
                               .width(px(40)).height(px(40)).clipped()
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)),
                                      Box().width(px(40)).height(px(40)).clipped()))
                  }),

        // MARK: self AND paint-only
        MatrixRow(name: "background(_:)", path: "legacy Element",
                  kinds: [.selfStorage, .paintOnly],
                  note: "writes Decoration.background; emits one rect and moves no number",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in Box().width(px(40)).height(px(40)) },
                       try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(40)).height(px(40)).background(.accent)
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)),
                                      Box().width(px(40)).height(px(40)).background(.accent)))
                  }),
        MatrixRow(name: "cornerRadius(_:)", path: "legacy Element",
                  kinds: [.selfStorage, .paintOnly],
                  note: "rounds the receiver's own fill. Both arms carry a background, so the "
                      + "rect exists either way and only its radii move",
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(40)).height(px(40)).background(.accent)
                       },
                       try observe(probe: pt(2, 2)) { _ in
                           Box().width(px(40)).height(px(40)).background(.accent)
                               .cornerRadius(px(12))
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)).background(.accent),
                                      Box().width(px(40)).height(px(40)).background(.accent)
                                          .cornerRadius(px(12))))
                  }),
        MatrixRow(name: "hoverBackground(_:), genuinely hovered", path: "legacy Element",
                  kinds: [.selfStorage, .paintOnly],
                  note: "the pointer is over the subject in BOTH arms, so what differs is the "
                      + "declaration and not the state",
                  arms: {
                      let hover: @MainActor (Window, FakePlatformWindow) -> Void = { _, platform in
                          platform.simulateInput(.mouseMoved(MouseEvent(position: pt(20, 20))))
                      }
                      return (try observe(probe: pt(2, 2), interact: hover) { counter in
                                  Box().width(px(40)).height(px(40)).background(.surface)
                                      .onClick { counter.bump() }
                              },
                              try observe(probe: pt(2, 2), interact: hover) { counter in
                                  Box().width(px(40)).height(px(40)).background(.surface)
                                      .hoverBackground(.accent).onClick { counter.bump() }
                              },
                              storageDiffers(Box().width(px(40)).height(px(40)).background(.surface),
                                             Box().width(px(40)).height(px(40)).background(.surface)
                                                 .hoverBackground(.accent)))
                  }),
        MatrixRow(name: "focusBackground(_:), genuinely focused", path: "legacy Element",
                  kinds: [.selfStorage, .paintOnly],
                  note: "focus drawing has exactly ONE spelling today and it is a fill — the "
                      + "hole lane 2 closes with `focusBorder`",
                  arms: {
                      let focus: @MainActor (Window, FakePlatformWindow) -> Void = { window, _ in
                          if let first = window.lastHitboxes.first { window.focus(first.id) }
                      }
                      return (try observe(probe: pt(2, 2), interact: focus) { counter in
                                  Box().width(px(40)).height(px(40)).background(.surface)
                                      .focusable().onClick { counter.bump() }
                              },
                              try observe(probe: pt(2, 2), interact: focus) { counter in
                                  Box().width(px(40)).height(px(40)).background(.surface)
                                      .focusBackground(.separator)
                                      .focusable().onClick { counter.bump() }
                              },
                              storageDiffers(Box().width(px(40)).height(px(40)).background(.surface),
                                             Box().width(px(40)).height(px(40)).background(.surface)
                                                 .focusBackground(.separator)))
                  }),

        // MARK: self AND prepaint-only
        MatrixRow(name: "onClick(_:)", path: "legacy Element",
                  kinds: [.selfStorage, .prepaintOnly],
                  note: "the ONLY thing that makes an element an opaque pointer target; it "
                      + "emits nothing and moves nothing",
                  arms: {
                      (try observe(probe: pt(20, 20)) { _ in Box().width(px(40)).height(px(40)) },
                       try observe(probe: pt(20, 20)) { counter in
                           Box().width(px(40)).height(px(40)).onClick { counter.bump() }
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)),
                                      Box().width(px(40)).height(px(40)).onClick { }))
                  }),

        // MARK: self AND prepaint-only (plan task 5, lane 3)
        //
        // Both arms carry an `onClick`, because neither modifier CREATES a hit
        // region (`OM-AB`): the bare arm registers the 40x40 box and is hit at
        // the (2, 2) probe, so the declared arm's zero is the modifier and not
        // a fixture that never registered. `.contentShape(inset: 10)` leaves a
        // (10, 10) 20x20 region the probe misses; `.allowsHitTesting(false)`
        // leaves no region at all.
        MatrixRow(name: "contentShape(inset:)", path: "legacy Element",
                  kinds: [.selfStorage, .prepaintOnly],
                  note: "insets the region an onClick registers (OM-J); configures, never "
                      + "creates (OM-AB); moves no rect and no node (probe L7)",
                  arms: {
                      (try observe(probe: pt(2, 2)) { counter in
                           Box().width(px(40)).height(px(40)).onClick { counter.bump() }
                       },
                       try observe(probe: pt(2, 2)) { counter in
                           Box().width(px(40)).height(px(40)).onClick { counter.bump() }
                               .contentShape(inset: px(10))
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)).onClick { },
                                      Box().width(px(40)).height(px(40)).onClick { }
                                          .contentShape(inset: px(10))))
                  }),
        MatrixRow(name: "allowsHitTesting(_:)", path: "legacy Element",
                  kinds: [.selfStorage, .prepaintOnly],
                  note: "a scope over the receiver's OWN hitbox and its subtree's (OM-T, probe "
                      + "N1); moves no rect and no node (probe L5)",
                  arms: {
                      (try observe(probe: pt(2, 2)) { counter in
                           Box().width(px(40)).height(px(40)).onClick { counter.bump() }
                       },
                       try observe(probe: pt(2, 2)) { counter in
                           Box().width(px(40)).height(px(40)).onClick { counter.bump() }
                               .allowsHitTesting(false)
                       },
                       storageDiffers(Box().width(px(40)).height(px(40)).onClick { },
                                      Box().width(px(40)).height(px(40)).onClick { }
                                          .allowsHitTesting(false)))
                  }),

        // MARK: distributes
        MatrixRow(name: "padding(_:)", path: "legacy Component", kinds: [.distributes, .wraps],
                  note: "a WRAP PER MEMBER (lane 4, OM-D): one node around each top-level "
                      + "node, each member keeping its own size. Before lane 4 it was an amend "
                      + "writing CSS border-box Style.padding onto each member — `distributes` "
                      + "alone, whose witness was the member's own size changing (OM-AD); a "
                      + "per-member wrap leaves that size unchanged by construction, so the "
                      + "row claims both kinds and the witness branches (OM-AM)",
                  memberCount: 2,
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in TwoMembers() },
                       try observe(probe: pt(2, 2)) { _ in TwoMembers().padding(px(20)) },
                       nil)
                  }),
        MatrixRow(name: "width(_:)", path: "legacy Component", kinds: [.distributes],
                  note: "an amend that OVERWRITES each member's own declared width (OM-F); "
                      + "SwiftUI's .frame wraps and keeps it. Frozen here, task 4's to change",
                  memberCount: 2,
                  arms: {
                      (try observe(probe: pt(2, 2)) { _ in TwoMembers() },
                       try observe(probe: pt(2, 2)) { _ in TwoMembers().width(px(70)) },
                       nil)
                  }),
    ]

    // The table must exercise every kind, or a kind's witness is unproven code
    // and the matrix has a column nothing reads.
    let covered = Set(rows.flatMap(\.kinds))
    #expect(covered == Set(Kind.allCases),
            why("the matrix leaves \(Set(Kind.allCases).subtracting(covered).map(\.rawValue).sorted()) "
                + "unexercised — every kind needs at least one row"))

    for row in rows {
        let label = "\(row.name) on the \(row.path) path"
        let (bare, declared, storage) = try row.arms()

        let nodeDelta = declared.nodeCount - bare.nodeCount
        let outerSizeDelta = declared.outerWidth - bare.outerWidth
        let rectsMoved = declared.rects != bare.rects
        let hitRegionsMoved = declared.hitRegions != bare.hitRegions
        let hitCountDelta = declared.hitCountAtEdge - bare.hitCountAtEdge

        // The instrument check, and it runs BEFORE any kind is derived (OM-X):
        // two arms that agree everywhere are a broken fixture, and a row that
        // classified one as "inert" would be the audit agreeing with itself.
        let reading = "bare \(bare) / declared \(declared) / storageDiffers \(String(describing: storage))"
        try #require(bare != declared || storage == true,
                     why("\(label): BROKEN INSTRUMENT — the two arms measure identically in all five "
                         + "components and in storage, so nothing here could classify anything. "
                         + reading))

        if row.kinds.contains(.wraps) {
            #expect(nodeDelta > 0,
                    "\(label) claims `wraps` and added no layout node. \(reading)")
            #expect(outerSizeDelta > 0,
                    "\(label) claims `wraps` and the container saw no bigger box. \(reading)")
        } else {
            #expect(nodeDelta == 0,
                    "\(label) does not claim `wraps` and added \(nodeDelta) layout node(s). \(reading)")
        }

        if row.kinds.contains(.selfStorage) {
            #expect(nodeDelta == 0,
                    "\(label) claims `self` and added a layout node. \(reading)")
            #expect(storage == true,
                    why("\(label) claims `self` and wrote nothing into the outermost layer's "
                        + "Style/Decoration/Handlers/elementID. \(reading)"))
        }

        if row.kinds.contains(.paintOnly) {
            #expect(nodeDelta == 0 && outerSizeDelta == 0,
                    why("\(label) claims `paint-only` and moved a number the engine produced "
                        + "(node \(nodeDelta), outer \(outerSizeDelta)). \(reading)"))
            #expect(rectsMoved,
                    "\(label) claims `paint-only` and emitted byte-identical rects. \(reading)")
        } else if !row.kinds.contains(.distributes) {
            #expect(!rectsMoved,
                    "\(label) does not claim `paint-only` and changed what is emitted. \(reading)")
        }

        if row.kinds.contains(.prepaintOnly) {
            #expect(nodeDelta == 0 && outerSizeDelta == 0 && !rectsMoved,
                    "\(label) claims `prepaint-only` and moved layout or paint. \(reading)")
            #expect(hitRegionsMoved || hitCountDelta != 0,
                    why("\(label) claims `prepaint-only` and changed nothing about hit testing. "
                        + reading))
        } else {
            #expect(!hitRegionsMoved && hitCountDelta == 0,
                    why("\(label) does not claim `prepaint-only` and moved a hit region or a click "
                        + "count. \(reading)"))
        }

        if row.kinds.contains(.distributes) {
            let members = try #require(row.memberCount,
                                       why("\(label) claims `distributes` without saying how many "
                                           + "top-level nodes its component has"))
            try #require(bare.rectSizes.count == members && declared.rectSizes.count == members,
                         why("\(label): set up — each member must paint exactly one rect, got "
                             + "\(bare.rectSizes.count) and \(declared.rectSizes.count). \(reading)"))
            if row.kinds.contains(.wraps) {
                // A wrap PER MEMBER (OM-AM): exactly one new node per member —
                // one around the whole group reads 1, an amend 0 — and each
                // member's OWN size unchanged, because what grew is its
                // wrapper. The `wraps` witness above already required the
                // container to see a bigger box.
                #expect(nodeDelta == members,
                        why("\(label) claims `distributes` + `wraps` and added \(nodeDelta) node(s) "
                            + "for \(members) members — one wrapper per member, not one around "
                            + "the group and not an amend. \(reading)"))
                for (index, pair) in zip(bare.rectSizes, declared.rectSizes).enumerated() {
                    #expect(pair.0 == pair.1,
                            why("\(label) claims a wrap per member and member \(index)'s own size "
                                + "moved (\(pair.0) → \(pair.1)) — that is an amend, not a wrap. "
                                + reading))
                }
            } else {
                #expect(nodeDelta == 0,
                        why("\(label) claims `distributes` and the modified component gained a node of "
                            + "its own — a Component is layout-transparent. \(reading)"))
                for (index, pair) in zip(bare.rectSizes, declared.rectSizes).enumerated() {
                    #expect(pair.0 != pair.1,
                            why("\(label) claims `distributes` and member \(index) kept its size "
                                + "(\(pair.0)) — the modifier reached some members and not all of "
                                + "them. \(reading)"))
                }
            }
        }
    }
}

// MARK: - Order-sensitive chains

/// **A legacy chain's `.background` covers the box as it stood where the
/// background was written** — SwiftUI's answer, for free, and the reason the
/// migration did not have to touch it (`OM-C`).
///
/// Probe `swiftui-outer-modifier-order`, arms A1 and A2: a 20x20 leaf reads a
/// background rect of `(0, 0) 36x36` when the padding is written first and
/// `(8, 8) 20x20` when the background is. Those are the two numbers below.
///
/// The mechanism is `ModifiedElement`'s four `StyledElement` accessors reading
/// and writing `outermost`: `.background` after `.padding` configures the
/// padding layer, and `.padding` after `.background` puts a fresh, undecorated
/// layer outside the decorated one.
///
/// **The two arms must disagree before either is believed.** They are the same
/// three modifiers in two orders; if a future change collapsed them onto one
/// layer the rects would coincide and both assertions below would still pass
/// against a chain that had lost its order entirely.
@Test @MainActor func aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    @MainActor func accentRect<E: Element>(_ make: @escaping @MainActor () -> E) throws -> MUIRect {
        let (window, _) = try makeFakeWindow(device: device, size: 200) {
            // Stage 6b (`LR-DG`, R-fill): the window's extent declared on the
            // row's two auto axes, so it sits at (0, 0) on both authorities.
            Row { make() }.alignItems(.flexStart).width(px(200)).height(px(200))
        }
        window.drawFrameIfNeeded()
        let theme = window.theme
        let want = theme[.accent]
        return try #require(window.lastScene.rects.first {
            $0.background.h == want.h && $0.background.s == want.s
                && $0.background.l == want.l && $0.background.a == want.a
        }, "nothing painted the accent token")
    }

    let paddedThenFilled = try accentRect {
        Box().width(px(20)).height(px(20)).padding(px(8)).background(.accent)
    }
    let filledThenPadded = try accentRect {
        Box().width(px(20)).height(px(20)).background(.accent).padding(px(8))
    }
    // **Two-layer arms, and they are not decoration.** Both chains above are
    // ONE `ModifierLayer` (`inner` empty), so `ModifiedElement.paint`'s loop
    // over the inner layers never runs and a fill emitted at the wrong layer's
    // bounds is invisible. Measured: filling the outermost decoration at
    // `pass.bounds(of: layout.inner[0].node)` instead of `bounds` reddened
    // nothing at all until these two arms existed.
    //
    // `.padding(4).padding(4).background` is A1 reached through E1: two layers,
    // the OUTERMOST one decorated, so the fill is the full (0,0) 36x36.
    // `.padding(8).background.padding(4)` is probe arm A3 exactly: outer 44x44
    // with the INNER layer's fill at (4,4) 36x36.
    let twoLayersOutermostFilled = try accentRect {
        Box().width(px(20)).height(px(20)).padding(px(4)).padding(px(4)).background(.accent)
    }
    let twoLayersInnerFilled = try accentRect {
        Box().width(px(20)).height(px(20)).padding(px(8)).background(.accent).padding(px(4))
    }

    try #require(describe(paddedThenFilled) != describe(filledThenPadded),
                 "the two orders painted the same rect — this chain has no order to test")
    try #require(describe(twoLayersOutermostFilled) != describe(twoLayersInnerFilled),
                 why("the two two-layer orders painted the same rect — the layer a fill belongs "
                     + "to is not observable in this fixture"))

    #expect(paddedThenFilled.bounds.origin.x == 0 && paddedThenFilled.bounds.origin.y == 0
                && paddedThenFilled.bounds.size.width == 36
                && paddedThenFilled.bounds.size.height == 36,
            why("`.padding(8).background` fills the PADDED box, SwiftUI A1's (0,0) 36x36; got "
                + describe(paddedThenFilled)))
    #expect(filledThenPadded.bounds.origin.x == 8 && filledThenPadded.bounds.origin.y == 8
                && filledThenPadded.bounds.size.width == 20
                && filledThenPadded.bounds.size.height == 20,
            why("`.background.padding(8)` fills the INNER box, SwiftUI A2's (8,8) 20x20; got "
                + describe(filledThenPadded)))
    #expect(twoLayersOutermostFilled.bounds.origin.x == 0
                && twoLayersOutermostFilled.bounds.origin.y == 0
                && twoLayersOutermostFilled.bounds.size.width == 36
                && twoLayersOutermostFilled.bounds.size.height == 36,
            why("`.padding(4).padding(4).background` fills the OUTERMOST layer's box, (0,0) "
                + "36x36; got " + describe(twoLayersOutermostFilled)))
    #expect(twoLayersInnerFilled.bounds.origin.x == 4 && twoLayersInnerFilled.bounds.origin.y == 4
                && twoLayersInnerFilled.bounds.size.width == 36
                && twoLayersInnerFilled.bounds.size.height == 36,
            why("`.padding(8).background.padding(4)` fills the INNER layer's box, SwiftUI A3's "
                + "(4,4) 36x36 inside a 44x44 outer; got " + describe(twoLayersInnerFilled)))
}

/// **Two `.padding` calls accumulate; they do not replace** — SwiftUI's E1/E2/E3
/// (`.padding(4).padding(4)` is `.padding(8)`), and `ModifiedElement`'s
/// `_wrap` appending rather than assigning is the mechanism (`OM-E`).
///
/// The control is `.padding(4)` alone: without it, "accumulates" and "the last
/// call wins" both put the leaf somewhere, and only a third reading says which.
/// `.padding(4)` alone puts the leaf at 4 and the outer box at 28 — numbers
/// neither of the other two arms can produce.
///
/// This is the `Element` half of a claim whose `Component` half is
/// `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement`
/// (`ComponentTests.swift`, lane 4) — which replaced
/// `chainedPaddingReplacesRatherThanAccumulates`, the amend-era pin of the
/// opposite answer.
@Test @MainActor func legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    /// The leaf's own rect and the outer width the marker reports.
    @MainActor func leafAndOuter<E: Element>(_ make: @escaping @MainActor () -> E)
        throws -> (leaf: MUIRect, outer: Float) {
        let (window, _) = try makeFakeWindow(device: device, size: 200) {
            // Stage 6b (`LR-DG`, R-fill): the window's extent declared on the
            // row's two auto axes, so it sits at (0, 0) on both authorities.
            Row {
                make()
                Box().width(px(1)).height(px(1)).background(.separator)
            }.alignItems(.flexStart).width(px(200)).height(px(200))
        }
        window.drawFrameIfNeeded()
        let rects = window.lastScene.rects
        let leaf = try #require(rects.first { $0.bounds.size.width == 20 && $0.bounds.size.height == 20 },
                                "the 20x20 leaf painted no rect")
        let marker = try #require(rects.first { $0.bounds.size.width == 1 && $0.bounds.size.height == 1 },
                                  "the marker painted no rect")
        return (leaf, marker.bounds.origin.x)
    }

    let twice = try leafAndOuter {
        Box().width(px(20)).height(px(20)).background(.accent).padding(px(4)).padding(px(4))
    }
    let once = try leafAndOuter {
        Box().width(px(20)).height(px(20)).background(.accent).padding(px(8))
    }
    let single = try leafAndOuter {
        Box().width(px(20)).height(px(20)).background(.accent).padding(px(4))
    }

    // The control, first: a chain that REPLACED would read `single`'s numbers
    // here, so the two must disagree before "twice == once" means anything.
    try #require(twice.outer != single.outer,
                 why("`.padding(4).padding(4)` measured the same as `.padding(4)` — this instrument "
                     + "cannot tell accumulation from replacement"))

    #expect(twice.outer == 36 && once.outer == 36,
            "both spellings must be SwiftUI E1's 36 wide; got \(twice.outer) and \(once.outer)")
    #expect(single.outer == 28, "the control, `.padding(4)`, is 28 wide; got \(single.outer)")
    #expect(twice.leaf.bounds.origin.x == 8 && twice.leaf.bounds.origin.y == 8,
            why("the leaf sits at (8, 8) under two 4s; got " + describe(twice.leaf)))
    #expect(describe(twice.leaf) == describe(once.leaf),
            why("`.padding(4).padding(4)` must paint exactly what `.padding(8)` paints; got "
                + describe(twice.leaf) + " against " + describe(once.leaf)))
}

/// **PINNED WRONG ON PURPOSE.** A padded click target is hittable in its
/// padding, where SwiftUI's is not (`OM-K`), **and MetalUI's two orders
/// disagree where SwiftUI's agree**.
///
/// Probe `swiftui-content-shape-hit-region`, arms P1 and P2: SwiftUI reads
/// `centre 1 / edge 0` for `.padding(80).onTapGesture` AND for
/// `.onTapGesture.padding(80)` — the padding is not part of the hit region in
/// either order, because SwiftUI derives the region from what the view draws.
/// A `.background` declared before the gesture (P4) makes the padding hittable,
/// which is the filled-panel case every real caller writes, so the divergence
/// is narrow: a padded, background-LESS click target.
///
/// MetalUI's default hit region is the element's whole frame, so:
///
/// - `.padding(80).onClick` registers at the OUTERMOST layer — the padded box —
///   and the edge is hit. SwiftUI says 0, MetalUI says 1. **Divergence.**
/// - `.onClick.padding(80)` leaves the handler on the inner `Box` and wraps an
///   undecorated layer around it, so the edge is NOT hit. The same number as
///   SwiftUI, arrived at by a different mechanism — and, unlike SwiftUI's, it
///   is order-sensitive.
///
/// Changing this would make a padded row unclickable at its edges;
/// `contentShape(inset:)` (lane 3) is the opt-in instead.
@Test @MainActor func aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    /// Clicks once at `point` in a fresh window and reports whether the handler ran.
    @MainActor func hits<E: Element>(at point: Point<Pixels>,
                                     _ make: @escaping @MainActor (ClickCounter) -> E) throws -> Int {
        let counter = ClickCounter()
        let (window, platform) = try makeFakeWindow(device: device, size: 200) {
            // Stage 6b (`LR-DG`, R-fill): the window's extent declared on the
            // row's two auto axes, so it sits at (0, 0) on both authorities.
            Row { make(counter) }.alignItems(.flexStart).width(px(200)).height(px(200))
        }
        window.drawFrameIfNeeded()
        platform.simulateInput(.mouseDown(MouseEvent(position: point)))
        platform.simulateInput(.mouseUp(MouseEvent(position: point)))
        return counter.count
    }

    // 20x20 inside 80 of padding: the outer box is 180x180, the inner one sits
    // at (80, 80). (5, 5) is deep in the padding and nowhere near the leaf;
    // (90, 90) is the leaf's own middle.
    let edge = pt(5, 5)
    let centre = pt(90, 90)

    let paddedThenClickable = { @MainActor (counter: ClickCounter) in
        Box().width(px(20)).height(px(20)).padding(px(80)).onClick { counter.bump() }
    }
    let clickableThenPadded = { @MainActor (counter: ClickCounter) in
        Box().width(px(20)).height(px(20)).onClick { counter.bump() }.padding(px(80))
    }

    // Both orders must be live at the centre, or an "edge 0" reading below
    // would only mean the fixture never registered a handler at all.
    try #require(hits(at: centre, paddedThenClickable) == 1,
                 "set up — `.padding(80).onClick` must be hittable at its centre")
    try #require(hits(at: centre, clickableThenPadded) == 1,
                 "set up — `.onClick.padding(80)` must be hittable at its centre")

    let paddedEdge = try hits(at: edge, paddedThenClickable)
    let clickableEdge = try hits(at: edge, clickableThenPadded)

    // **A two-layer arm, and it is not decoration.** Both chains above are ONE
    // `ModifierLayer`, so `prepaintLayerBody`'s recursion — which is what pairs
    // a layer's handlers with that layer's own box — never runs, and a chain
    // that registered every layer at the outermost box would read the same.
    // `.padding(40).onClick.padding(40)` puts the handler on the INNER layer,
    // whose box is 100x100 at (40, 40) inside a 180x180 outer: (50, 50) is
    // inside it and the edge is not.
    let clickableInTheMiddle = { @MainActor (counter: ClickCounter) in
        Box().width(px(20)).height(px(20)).padding(px(40)).onClick { counter.bump() }
            .padding(px(40))
    }
    let middleLayerInside = try hits(at: pt(50, 50), clickableInTheMiddle)
    let middleLayerEdge = try hits(at: edge, clickableInTheMiddle)
    #expect(middleLayerInside == 1,
            why("the handler-carrying INNER layer's own box (40…140) must be hit at (50, 50); "
                + "got \(middleLayerInside)"))
    #expect(middleLayerEdge == 0,
            why("and the OUTER layer, which carries no handler, must not be — (5, 5) is inside "
                + "it and outside the handler's layer; got \(middleLayerEdge)"))

    #expect(paddedEdge == 1,
            why("DIVERGENCE (OM-K): `.padding(80).onClick` is hit in its padding — SwiftUI's P1 "
                + "reads edge 0 and MetalUI reads edge \(paddedEdge)"))
    #expect(clickableEdge == 0,
            why("`.onClick.padding(80)` keeps the handler on the inner box, so the padding is not "
                + "hit; got \(clickableEdge)"))
    #expect(paddedEdge != clickableEdge,
            why("DIVERGENCE (OM-K, extended): MetalUI's two orders must DISAGREE at the edge where "
                + "SwiftUI's P1 and P2 agree — only the outermost layer carries handlers"))
}

/// **PINNED WRONG ON PURPOSE.** `.cornerRadius(_:)` rounds the element's own
/// fill and **does not clip its children** (`OM-G`), where SwiftUI's
/// `.cornerRadius` clips what was declared before it (probe
/// `swiftui-border-clip-paint`, arm C1).
///
/// The arms that must disagree are inside one scene: the parent's own rect
/// carries the radius — so the modifier is live, not ignored — while the
/// child's rect comes out with the **whole surface** as its `contentMask` and
/// all-zero `maskCornerRadii`. A test that only read the child would pass
/// against a `cornerRadius` that did nothing whatsoever.
///
/// The second control is a `ScrollView`, the one thing in the framework that
/// does push a clip: its child's `contentMask` is the viewport, not the
/// surface. Without it, "the mask is the whole surface" could be true because
/// `Frame.fill` never writes a mask at all.
///
/// `.clipped()` (lane 2) is the opt-in; making `.cornerRadius` clip by default
/// would move all sixteen of the demo's call sites and is task 11's.
@Test @MainActor func aBareCornerRadiusDoesNotClipTheChildren() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")

    // `.flexShrink(0)` on the child is load-bearing: without it the 60x60 child
    // is shrunk to the 40pt parent's width and never overflows at all, so
    // "unclipped" and "clipped exactly to the box" would read the same. Measured
    // on the first run of this test — the child came back 40x60.
    let (window, _) = try makeFakeWindow(device: device, size: 200) {
        Row {
            Box {
                Box().width(px(60)).height(px(60)).flexShrink(0).background(.surface)
            }
            .width(px(40)).height(px(40)).background(.accent).cornerRadius(px(12))
        }.alignItems(.flexStart)
    }
    window.drawFrameIfNeeded()

    let theme = window.theme
    @MainActor func rect(_ token: ColorToken) throws -> MUIRect {
        let want = theme[token]
        return try #require(window.lastScene.rects.first {
            $0.background.h == want.h && $0.background.s == want.s
                && $0.background.l == want.l && $0.background.a == want.a
        }, "nothing painted \(token)")
    }

    let parent = try rect(.accent)
    let child = try rect(.surface)

    // Control 1: the radius IS live on the element that declared it.
    try #require(parent.cornerRadii.topLeft == 12,
                 why("set up — the parent's own fill must carry the 12pt radius, or this test says "
                     + "nothing about clipping; got " + describe(parent)))

    // Control 2: a mask that is NOT the whole surface is reachable and this
    // instrument can see one.
    let (scroller, _) = try makeFakeWindow(device: device, size: 200) {
        Box {
            ScrollView(.vertical, elementID: ElementID("scroller")) {
                Box().width(px(60)).height(px(60)).flexShrink(0).background(.surface)
            }
        }.width(px(40)).height(px(40))
    }
    scroller.drawFrameIfNeeded()
    let scrollerWant = scroller.theme[ColorToken.surface]
    let clipped = try #require(scroller.lastScene.rects.first {
        $0.background.h == scrollerWant.h && $0.background.s == scrollerWant.s
            && $0.background.l == scrollerWant.l && $0.background.a == scrollerWant.a
    }, "the ScrollView control painted nothing")
    try #require(clipped.contentMask.size.width != 200 || clipped.contentMask.size.height != 200,
                 why("set up — the ScrollView control must produce a mask narrower than the surface, "
                     + "or `mask == surface` below proves nothing; got " + describe(clipped)))

    #expect(child.contentMask.origin.x == 0 && child.contentMask.origin.y == 0
                && child.contentMask.size.width == 200 && child.contentMask.size.height == 200,
            why("DIVERGENCE (OM-G): a bare `.cornerRadius` pushes no clip, so the child keeps the "
                + "whole surface as its mask; got " + describe(child)))
    #expect(child.maskCornerRadii.topLeft == 0 && child.maskCornerRadii.topRight == 0
                && child.maskCornerRadii.bottomRight == 0 && child.maskCornerRadii.bottomLeft == 0,
            why("DIVERGENCE (OM-G): and no rounded mask either; got " + describe(child)))
    #expect(child.bounds.size.width == 60 && child.bounds.size.height == 60,
            why("the child overflows its rounded parent at full size; got " + describe(child)))
}
