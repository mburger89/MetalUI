import Foundation
import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 5 of the engine replacement — **lane 1**, the presentation
// root. Design: `docs/superpowers/specs/2026-09-23-engine-stage-5-design.md` §4 and
// §7 lane 1 (rulings `LR-CH`…`LR-CM`, as amended by `LR-CP`).
//
// Under the proposal authority a `Deferred` whose one content node is
// `.position(.absolute)` is a **presentation root**: its content is lowered as
// padding inside a window-sized frame (`LR-CI`), laid out in its own native run
// before the root (`LR-CM`), and the `Deferred` hands its parent a 0×0 placeholder
// every lowered container drops (`LR-CK`). Every tree whose legacy containing
// block is not the window reported by name (`LR-CL`) until stage 9.
//
// **Stage 9** (record §51, lane 1; rulings `LR-FE`, `LR-FF`): the legacy engine
// is deleted, so each test keeps its lowered literals and loses its agreement
// check (1.1's and 1.4's hitboxes and scene gain literals), 1.5 loses its seven
// containing-block arms — their reports die with the legacy containing block in
// lane 3, whose `PresentationContainingBlockTests` pins the window answer — and
// gains divergence 11's proposal fact, and 1.6 (the production trap on
// `deferred.containingBlock`) retires.
//
// **Diagnostics are compared by their printed description** (`"box.position"`),
// not by `UnlowerableField` values, so that this file compiled against the source
// before `LoweringSite.deferred` existed and its red-before could be taken by
// running it (record §29, lane 1).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func dim(_ v: Float) -> MetalUICore.Dimension { .length(.pixels(Pixels(v))) }
private let pRoot = GlobalElementID.child(of: nil, at: 0, name: nil)
private func pChild(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}
private func pBounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}
private func insets(top: MetalUICore.Dimension = .auto, right: MetalUICore.Dimension = .auto,
                    bottom: MetalUICore.Dimension = .auto,
                    left: MetalUICore.Dimension = .auto) -> Edges<MetalUICore.Dimension> {
    Edges(top: top, right: right, bottom: bottom, left: left)
}

/// A painted, clickable absolute box: a background so the scenes compare
/// something, a click handler so the hitboxes and accessibility records do.
@MainActor
private func absBox(_ edges: Edges<MetalUICore.Dimension>) -> Box<EmptyGroup> {
    Box().background(.accent).onClick {}.position(.absolute).inset(edges)
}

/// The proposal frame's diagnostics for `make()` rendered **as the frame's root**
/// (not inside the harness root, whose native node has no record and is the
/// window by construction), as printed descriptions.
@MainActor
private func rootDiagnostics<E: Element>(width: Float = 200, height: Float = 100,
                                         _ make: () -> E) -> [String] {
    rootFields(width: width, height: height, make).map(\.description)
}

/// `rootDiagnostics`' fields themselves, for an assertion on their owning stage.
@MainActor
private func rootFields<E: Element>(width: Float = 200, height: Float = 100,
                                    _ make: () -> E) -> [UnlowerableField] {
    var root = make()
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)), scaleFactor: 1,
                      reportsUnlowerableFields: true)
    frame.render(&root)
    return frame.unlowerableFields
}

/// Nothing was reported. (Until stage 9 this was `expectAgreement`, which also
/// required every observation to agree with the legacy engine's; that comparison
/// is the deleted concept, `LR-FE` item 2.)
@MainActor
private func expectNothingReported(_ r: LayoutDifferential.Report, _ arm: String,
                                   sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
}

private struct PresentingSolo: Component {
    var content: some ElementGroup {
        Deferred { absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(10)).cssHeight(px(10)) }
    }
}

private struct PresentingPair: Component {
    var content: some ElementGroup {
        Box().cssWidth(px(10)).cssHeight(px(10)).background(.surface)
        Deferred { absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(10)).cssHeight(px(10)) }
    }
}

// MARK: - 1.1 The placement, per inset shape

/// **1.1** (`LR-CI`). `LayoutDifferential.compare` at **200×100** — non-square on
/// purpose, so a width/height basis swap for a percentage is visible (`AP-D`) —
/// one arm per shape of spec §2.4 that lowers. Each arm puts `Box { Deferred {
/// absolute box } }` under the harness root, so the `Deferred` is received by a
/// lowered container (which drops its placeholder) and the harness root's native
/// node is the window. Each: no report, and the box's and the `Deferred`'s rect
/// equal to the legacy engine's measured answer. Until stage 9 every observation
/// was also compared with the legacy engine's; since then the box's hitbox (it has
/// an `onClick`) and its background — the two readers **M1c** names — are
/// literals at the same rect.
///
/// Red-before (at `e5caefb`'s source): every arm reports `[box.position,
/// box.inset]` (`[box.position]` for "none").
///
/// Mutations that must redden it: **M1a** the trailing alignment written as
/// leading (the right/bottom arm); **M1b** `top`'s percentage resolved against the
/// width (the percent arm: y 100 against 50); **M1c** W registered but not aliased
/// (the stretched arms: the element's rect and its background); **M1d** the
/// placeholder's alias removed (every arm's `Deferred` id reads 0×0).
@MainActor
@Test func aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape() throws {
    typealias Arm = (name: String, report: LayoutDifferential.Report, deferredIndex: Int, expected: Bounds<Pixels>)
    var arms: [Arm] = []
    func arm<C: ElementGroup>(_ name: String, deferredIndex: Int = 0, _ expected: Bounds<Pixels>,
                              @ElementBuilder _ make: @MainActor () -> C) {
        arms.append((name, LayoutDifferential.report(width: 200, height: 100, make), deferredIndex, expected))
    }
    arm("top/left px", pBounds(5, 5, 30, 20)) {
        Box { Deferred { absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(30)).cssHeight(px(20)) } }
    }
    arm("right/bottom px, declared size", pBounds(163, 71, 30, 20)) {
        Box { Deferred { absBox(insets(right: dim(7), bottom: dim(9))).cssWidth(px(30)).cssHeight(px(20)) } }
    }
    arm("all four, auto size (stretched on both axes)", pBounds(40, 10, 140, 60)) {
        Box { Deferred { absBox(insets(top: dim(10), right: dim(20), bottom: dim(30), left: dim(40))) } }
    }
    arm("left/right, auto width, declared height", pBounds(10, 0, 160, 20)) {
        Box { Deferred { absBox(insets(right: dim(30), left: dim(10))).cssHeight(px(20)) } }
    }
    arm("all four, declared size (the leading insets win)", pBounds(40, 10, 30, 20)) {
        Box {
            Deferred {
                absBox(insets(top: dim(10), right: dim(20), bottom: dim(30), left: dim(40)))
                    .cssWidth(px(30)).cssHeight(px(20))
            }
        }
    }
    // Divergence 9, on both authorities: no inset puts the box at the containing
    // block's origin, not at CSS's static position after the in-flow sibling.
    arm("no insets, after an in-flow sibling (divergence 9)", deferredIndex: 1, pBounds(0, 0, 30, 20)) {
        Box {
            Box().cssWidth(px(40)).cssHeight(px(20)).background(.surface)
            Deferred { absBox(insets()).cssWidth(px(30)).cssHeight(px(20)) }
        }
    }
    arm("percent: top against the height, left against the width", pBounds(50, 50, 10, 10)) {
        Box {
            Deferred {
                absBox(insets(top: .length(.percent(0.5)), left: .length(.percent(0.25))))
                    .cssWidth(px(10)).cssHeight(px(10))
            }
        }
    }
    arm("rem", pBounds(32, 16, 10, 10)) {
        Box {
            Deferred {
                absBox(insets(top: .length(.rems(Rems(1))), left: .length(.rems(Rems(2)))))
                    .cssWidth(px(10)).cssHeight(px(10))
            }
        }
    }
    arm("declared width 40, minWidth 50 (clamped on a declared axis, AP-E)", pBounds(5, 5, 50, 10)) {
        Box {
            Deferred {
                absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(40)).cssMinWidth(px(50)).cssHeight(px(10))
            }
        }
    }
    arm("margin, flexGrow and alignSelf present (dropped, as the legacy engine ignores them)",
        pBounds(5, 5, 30, 20)) {
        Box {
            Deferred {
                absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(30)).cssHeight(px(20))
                    .margin(px(7)).flexGrow(1).alignSelf(.center)
            }
        }
    }
    try #require(arms.count == 10)
    for arm in arms {
        expectNothingReported(arm.report, arm.name)
        let deferred = pChild(pChild(pRoot, 0), arm.deferredIndex), box = pChild(deferred, 0)
        #expect(arm.report.bounds[box] == arm.expected, "\(arm.name): lowered box \(String(describing: arm.report.bounds[box]))")
        #expect(arm.report.bounds[deferred] == arm.expected, "\(arm.name): lowered Deferred \(String(describing: arm.report.bounds[deferred]))")
        #expect(arm.report.hitboxRects[box] == arm.expected, "\(arm.name): hitbox \(String(describing: arm.report.hitboxRects[box]))")
        #expect(arm.report.sceneRects.contains(arm.expected), "\(arm.name): background \(arm.report.sceneRects)")
    }
}

// MARK: - 1.2, 1.3 The two deliberate proposal-only answers (`LR-CJ`)

/// **1.2** (`LR-CJ` item 2). A box stretched between insets leaving 10×10, with
/// padding 10 on every edge: the legacy engine floored the border box at the
/// padding sum (`BM-4`) — **20×20** at (100, 10); the lowering keeps the inset box
/// — **10×10** at (100, 10) — and lets the padding overflow, `LR-AH`/`LR-AW`'s
/// answer applied to the third place the question arises. Pinned by name.
///
/// Red-before: reports `[box.position, box.inset]`.
///
/// Mutation that must redden it: **M1e** W's minimum set to the padding + border
/// sum (lowered reads 20×20).
///
/// **Renamed at stage 9** from
/// `anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBoxWhereTheLegacyEngineFloorsIt`
/// (`LR-FE` item 6).
@MainActor
@Test func anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBox() throws {
    var padded = Style()
    padded.padding = Edges(all: .pixels(px(10)))
    let report = LayoutDifferential.report(width: 200, height: 100) {
        Box {
            Deferred {
                Box(style: padded).background(.accent)
                    .position(.absolute).inset(insets(top: dim(10), right: dim(90), bottom: dim(80), left: dim(100)))
            }
        }
    }
    #expect(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let box = pChild(pChild(pChild(pRoot, 0), 0), 0)
    #expect(report.bounds[box] == pBounds(100, 10, 10, 10), "lowered \(String(describing: report.bounds[box]))")
}

/// **1.3** (`LR-CJ` item 1; probe Q3). An auto-width `Text` with only a leading
/// inset of 150 in a 200×200 window: the legacy engine measures an absolute box
/// against the containing block's full width (`placeAbsolute` passes
/// `available: cb.size`), so the text wraps at 200 and overflows the window; the
/// lowering proposes the window minus the inset, SwiftUI's leading padding, so it
/// wraps at 50 and grows taller. Pinned by name.
///
/// Red-before: reports `[text.position, text.inset]`.
///
/// Mutation that must redden it: **M1f** the padding's leading edge forced to 0
/// (lowered x 0, the legacy width).
///
/// **Renamed at stage 9** from
/// `anAbsoluteTextWrapsAtTheWindowMinusItsInsetWhereTheLegacyEngineWrapsAtTheWindow`
/// (`LR-FE` item 6); its legacy literal ((150, 0) 196×32) went with the engine.
@MainActor
@Test func anAbsoluteTextWrapsAtTheWindowMinusItsInset() throws {
    let sentence = "The quick brown fox jumps over the lazy dog and it goes on"
    try #require(sentence.count == 58)
    let report = LayoutDifferential.report(width: 200, height: 200) {
        Box { Deferred { Text(sentence).position(.absolute).inset(insets(left: dim(150))) } }
    }
    #expect(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let text = pChild(pChild(pChild(pRoot, 0), 0), 0)
    let lowered = try #require(report.bounds[text])
    #expect(lowered.origin == Point(x: px(150), y: px(0)), "lowered \(lowered)")
    #expect(lowered.size.width.value <= 50 && lowered.size.height.value > 32, "lowered \(lowered)")
}

// MARK: - 1.4 Every lowered container drops the placeholder

/// **1.4** (`LR-CK`, as amended by `LR-CP` item 1). The placeholder a presentation
/// hands its parent is a 0×0 native leaf **every lowered container removes at
/// entry**, as the legacy engine filters an absolute child out of flow (`AP-B`).
/// Six parents, one per consumer: a gapped column (the third child at y **22** —
/// out of flow, no gap), a `Stack`, a `ScrollView`'s content, and — since
/// `Deferred` has no modifier surface, a `Component` whose body is the `Deferred`
/// is how a layer receives the placeholder directly — that component with
/// `.padding(4)` (the wrap op, `OM-D`), with `.frame(width: 50, height: 50)` (a
/// one-node frame layer), and a two-member one with the same `.frame` (the
/// per-member row, `LR-BH`). Each: no report, and — until stage 9, every
/// observation equal to the legacy engine's; since then literals — the absolute
/// box's hitbox at its window rect (5, 5) 10×10 in every arm, and the column's
/// third child at y 22.
///
/// Red-before: every arm reports `[box.position, box.inset]`.
///
/// Mutations that must redden it: **M1g** the filter removed from
/// `lowerLegacyNode` — measured (`LR-CQ`): **the column and `ScrollView` arms
/// only** here (plus 1.1's divergence-9 arm, 1.7 and the demo census); the
/// `Stack` and `.padding` arms agree under M1g, because a 0×0 child changes
/// neither a stack's union nor a one-child padding's answer, so those two sites'
/// filter is observable by nothing and these arms guard only that the drop does
/// not break them; **M1h**
/// removed from `lowerLegacyLayer`'s frame arm only — **the two-member `.frame`
/// arm only**, measured (lane 1's corrections, `LR-CQ`): over one node the
/// undropped 0×0 placeholder sits inside a fixed 50×50 frame whose answer does
/// not depend on it, and the `Deferred`'s rect is aliased to its content, so the
/// one-node arm agrees under M1h and cannot see it; **M1o** the frame arm's
/// `legacyFrameLayerDiagnostics` handed the **dropped** count (both `.frame` arms
/// report `[modifierLayer.style]`).
@MainActor
@Test func aPresentationPlaceholderIsDroppedByEveryLoweredContainer() throws {
    func presented() -> Deferred<Box<EmptyGroup>> {
        Deferred { absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(10)).cssHeight(px(10)) }
    }
    let column = LayoutDifferential.report(width: 200, height: 100) {
        Column(gap: px(12)) {
            Box().cssWidth(px(10)).cssHeight(px(10)).background(.surface)
            presented()
            Box().cssWidth(px(11)).cssHeight(px(10)).background(.surface)
        }
    }
    expectNothingReported(column, "gapped column")
    let third = pChild(pChild(pRoot, 0), 2)
    #expect(column.bounds[third]?.origin.y == px(22),
            "the column's third child: \(String(describing: column.bounds[third]))")
    let stack = LayoutDifferential.report(width: 200, height: 100) {
        Stack {
            Box().cssWidth(px(10)).cssHeight(px(10)).background(.surface)
            presented()
        }
    }
    expectNothingReported(stack, "Stack")
    let scroll = LayoutDifferential.report(width: 200, height: 100) {
        Box {
            ScrollView(.vertical) {
                presented()
                ProbeLeaf(width: 80, height: 200)
            }
        }
        .cssWidth(px(80)).cssHeight(px(60))
    }
    expectNothingReported(scroll, "ScrollView content")
    let wrap = LayoutDifferential.report(width: 200, height: 100) {
        Box { PresentingSolo().padding(px(4)) }
    }
    expectNothingReported(wrap, "Component .padding (the wrap op)")
    let oneNodeFrame = LayoutDifferential.report(width: 200, height: 100) {
        Box { PresentingSolo().frame(width: px(50), height: px(50)) }
    }
    expectNothingReported(oneNodeFrame, "one-node .frame layer")
    let twoMemberFrame = LayoutDifferential.report(width: 200, height: 100) {
        Box { PresentingPair().frame(width: px(50), height: px(50)) }
    }
    expectNothingReported(twoMemberFrame, "two-member .frame layer")
    // Every arm's absolute box really was laid out against the window: its hitbox
    // (the one `onClick` in each tree) is there — a literal since stage 9, where
    // the comparison carried it for the last four arms.
    for (name, report) in [("gapped column", column), ("Stack", stack), ("ScrollView content", scroll),
                           ("Component .padding", wrap), ("one-node .frame", oneNodeFrame),
                           ("two-member .frame", twoMemberFrame)] {
        #expect(report.frame.hitboxes.contains { $0.bounds == pBounds(5, 5, 10, 10) },
                "\(name): hitboxes \(report.frame.hitboxes.map(\.bounds))")
    }
    for (name, report, deferred) in [
        ("gapped column", column, pChild(pChild(pRoot, 0), 1)),
        ("Stack", stack, pChild(pChild(pRoot, 0), 1)),
    ] {
        #expect(report.bounds[pChild(deferred, 0)] == pBounds(5, 5, 10, 10),
                "\(name): \(String(describing: report.bounds[pChild(deferred, 0)]))")
    }
}

// MARK: - 1.5, 1.6 The containing block, reported by name (`LR-CL`)

/// **1.5** (`LR-CL`, `LR-CK`, `LR-CJ` item 3; `LR-CP` item 2). A plain `Frame`
/// under the proposal authority with diagnostics, the tree **as the root**; each
/// arm's report exactly. The containing block is the window by construction.
///
/// **Stage 9** (`LR-FF`, `LR-FG` item 4, `LR-FH` item 1): the seven arms whose
/// legacy containing block was not the window — a bordered root, a root declaring
/// width 100 in a 200 window, a `Deferred` root, a presentation inside a
/// top/left-5 presentation, a root `.frame(maxWidth: 100)`, a root
/// `.frame(minWidth: 300)`, and a presentation inside a **bordered** `inset(0)`
/// one — reported `deferred.containingBlock`, `deferred.root` or
/// `deferred.nested`; lane 3 deletes those reports with the legacy engine that
/// defined them, and its N3.1 (`PresentationContainingBlockTests`) pins the same
/// seven trees at the window rect with nothing reported. They are removed here,
/// not re-valued. **Added**: divergence 11's proposal fact (the one
/// `AbsoluteOverlayTests.anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`
/// held until lane 2 retires it) — an absolute box inside a `ScrollView` with no
/// `Deferred` is reported at its consumer, `[box.position, box.inset]`. Eighteen
/// arms become twelve. The remaining arms:
///
/// - a root declaring width 200, an auto root, a root `.frame(maxWidth: 300)` →
///   nothing (the last was the separating arm of the removed clamped-frame arms);
/// - a presentation inside an `inset(0)` one → nothing (its padding box is the
///   window);
/// - an absolute box in a column with no `Deferred` → `[box.position, box.inset]`
///   at the consumer; an absolute root → the `.unconsumed` pair;
/// - `minWidth` on an absolute box's `auto` axis → `box.minSize.absolute`;
///   `maxHeight` on one → `box.maxSize.absolute`; a percentage `minWidth` on a
///   declared axis → `box.minSize.percent` (lane 1's corrections, `LR-CQ`);
/// - an absolute box inside a `ScrollView`, no `Deferred` → `[box.position,
///   box.inset]` (divergence 11's proposal fact, stage 9);
/// - `Component().width(70)` over a `Deferred`-absolute member → `deferred.amended`;
/// - and every `<field>.absolute` the frame reports is a **permanent refusal**
///   (`owner == nil`) since stage 10 (`LR-FO` item 2; it read stage 8 until
///   stage 8, then stage 10 — `LR-CQ`, `LR-EZ` item 3).
///
/// Stage 10 lane 1 removed the "inside a `.relative` ancestor" arm (its field,
/// `Position.relative`, is deleted by lane 2, `LR-FM` item 1): twelve arms
/// become eleven.
///
/// Red-before: every `Deferred` arm reads `[box.position, box.inset]`; the
/// absolute-root arm reads `[box.position, box.inset]`.
///
/// Mutations that must redden it: **M1k** `coversWindow` always false (the
/// `inset(0)` arm reads `[deferred.nested]`, until lane 3 deletes the nested
/// check); **M1l** `planLegacyItems`' `position` entry deleted (the column and
/// `ScrollView` arms read `[box.inset]`). Lane 1's corrections (`LR-CQ`) add
/// **M1q** `owningStage` for `.absolute` → "2" (the stage-8 assertion; since
/// stage 10 the property is `owner`, and the assertion reads `nil`); **M1r**
/// the `maxSize.absolute` report deleted (the `maxHeight` arm reads `[]`, and the
/// owning-stage `#require`); **M1s** the `minSize.percent` report deleted (the
/// percentage arm reads `[]`). M1i, M1j, M1p and M1t targeted the removed arms'
/// checks (stage 9).
@MainActor
@Test func aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName() throws {
    func presented() -> Deferred<Box<EmptyGroup>> {
        Deferred { absBox(insets(right: dim(5), bottom: dim(5))).cssWidth(px(10)).cssHeight(px(10)) }
    }
    typealias Arm = (name: String, got: [String], expected: [String])
    var arms: [Arm] = []
    arms.append(("root width 200", rootDiagnostics { Box { presented() }.cssWidth(px(200)) }, []))
    arms.append(("auto root", rootDiagnostics { Box { presented() } }, []))
    arms.append(("inside an inset(0) presentation", rootDiagnostics {
        Box { Deferred { Box { presented() }.background(.surface).position(.absolute).inset(px(0)) } }
    }, []))
    arms.append(("absolute in a column, no Deferred", rootDiagnostics {
        Column { absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(10)).cssHeight(px(10)) }
    }, ["box.position", "box.inset"]))
    // Stage 9: divergence 11's proposal fact (`AbsoluteOverlayTests`' retired
    // `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`): an absolute
    // box in a `ScrollView` with no `Deferred` is reported at its consumer, the
    // scroller's lowered content node — site `box`, the box's own.
    arms.append(("absolute in a ScrollView, no Deferred", rootDiagnostics {
        Box {
            ScrollView(.vertical) {
                Box().cssWidth(px(40)).cssHeight(px(40)).background(.accent)
                absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(22)).cssHeight(px(20))
            }
        }
        .cssWidth(px(60)).cssHeight(px(60))
    }, ["box.position", "box.inset"]))
    arms.append(("absolute root", rootDiagnostics {
        absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(10)).cssHeight(px(10))
    }, ["box.position.unconsumed", "box.inset.unconsumed"]))
    arms.append(("minWidth on an auto axis", rootDiagnostics {
        Box { Deferred { absBox(insets(top: dim(5), left: dim(5))).cssHeight(px(10)).cssMinWidth(px(50)) } }
    }, ["box.minSize.absolute"]))
    arms.append(("Component amend over a presentation member", rootDiagnostics {
        Box { PresentingSolo().width(px(70)) }
    }, ["deferred.amended"]))
    arms.append(("root .frame(maxWidth: 300) (the separating arm)", rootDiagnostics {
        Box { presented() }.frame(maxWidth: px(300))
    }, []))
    // Lane 1 corrections (`LR-CQ`): four claims the source made that no arm saw
    // (the fourth, the bordered `inset(0)` presentation, removed at stage 9).
    arms.append(("maxHeight on an auto axis", rootDiagnostics {
        Box { Deferred { absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(10)).cssMaxHeight(px(50)) } }
    }, ["box.maxSize.absolute"]))
    var percentMinimum = Style()
    percentMinimum.minSize.width = .length(.percent(0.5))
    arms.append(("percentage minWidth on a declared axis", rootDiagnostics {
        Box {
            Deferred {
                Box(style: percentMinimum).background(.accent).onClick {}.position(.absolute)
                    .inset(insets(top: dim(5), left: dim(5))).cssWidth(px(40)).cssHeight(px(10))
            }
        }
    }, ["box.minSize.percent"]))
    try #require(arms.count == 11)
    for arm in arms {
        #expect(arm.got == arm.expected, "\(arm.name): \(arm.got)")
    }
    // `<field>.absolute` belonged to stage 8's min/max recipe (`LR-CJ` item 3);
    // stage 8 made it stage 10's (`LR-EV` item 4, `LR-EZ` item 3: the public
    // spelling is a `.frame` before `.position`, which never reports), and stage
    // 10 made it a permanent refusal (`LR-FO` item 2: `minSize`/`maxSize`
    // survive, so the report cannot die with them). Read off the fields the
    // frame really reported, not off a hand-built value.
    let absoluteFields = rootFields {
        Box { Deferred { absBox(insets(top: dim(5), left: dim(5))).cssMinWidth(px(50)).cssMaxHeight(px(50)) } }
    }
    try #require(absoluteFields.map(\.description) == ["box.minSize.absolute", "box.maxSize.absolute"],
                 "\(absoluteFields)")
    for field in absoluteFields {
        #expect(field.owner == nil, "\(field) is owned by \(field.owner ?? "nobody")")
    }
}

// MARK: - 1.7 Presentations are laid out before the root (`LR-CM`)

/// **1.7** (`LR-CM`; `SA-M`). A presentation runs in its own native run **before**
/// the root's, so `LayoutTree.lastNativeLayoutWork` after the frame is the root's
/// own run: equal to the same tree's with the `Deferred` removed. A branching root
/// (two leaves and the dropped placeholder), and the presentation's box asserted
/// at its window rect, so the run it did is not vacuous.
///
/// Red-before: the tree with the `Deferred` reports, and its reported 0×0 leaf
/// sits in the root's flow, so the two roots' work differs.
///
/// Mutation that must redden it: **M1n** presentations laid out after the root.
@MainActor
@Test func presentationsAreLaidOutBeforeTheRootSoTheRootsWorkRecordIsUnchanged() throws {
    func frame<E: Element>(_ make: () -> E) -> Frame {
        var root = make()
        let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                          reportsUnlowerableFields: true, recordsElementBounds: true)
        frame.render(&root)
        return frame
    }
    let with = frame {
        Box {
            ProbeLeaf(width: 20, height: 10)
            ProbeLeaf(width: 30, height: 10)
            Deferred { absBox(insets(top: dim(5), left: dim(5))).cssWidth(px(10)).cssHeight(px(10)) }
        }
    }
    let without = frame {
        Box {
            ProbeLeaf(width: 20, height: 10)
            ProbeLeaf(width: 30, height: 10)
        }
    }
    #expect(with.unlowerableFields.isEmpty, "\(with.unlowerableFields)")
    try #require(without.unlowerableFields.isEmpty, "\(without.unlowerableFields)")
    #expect(with.elementBounds[pChild(pChild(pRoot, 2), 0)] == pBounds(5, 5, 10, 10),
            "the presentation's box: \(String(describing: with.elementBounds[pChild(pChild(pRoot, 2), 0)]))")
    let a = with.tree.lastNativeLayoutWork, b = without.tree.lastNativeLayoutWork
    try #require(b.cacheMisses > 0)
    #expect(a == b, "with the presentation \(a), without \(b)")
}

// MARK: - Stage 8: a framed box can be an absolute box (`LR-EV`)
//
// Plan task 7, stage 8, lane 1 (spec `docs/superpowers/specs/2026-09-24-engine-stage-8-design.md`
// §6, N1.2–N1.4; record §50). Stage 8 deprecates the sizing modifiers, so the
// recipe sizes an absolute box with a `.frame` written BEFORE `.position` (R6).
// Before `LR-EV` that spelling trapped a production frame: a `.position`/`.inset`
// written after a frame was compared as "a caller's modifier on the layer" and
// reported `modifierLayer.style`.

/// A2's old spelling, the deprecated own-box size (class D, `LR-EW`).
private struct FramedAbsoluteOldSpelling: DeprecatedSpelling {
    @available(*, deprecated, message: "spells the absolute box with the deprecated sizing modifiers on purpose: A0, the control of aFramedAbsoluteBoxIsAPresentationRoot (stage 8, LR-EW class D)")
    func spelled() -> Box<EmptyGroup> {
        Box().width(px(20)).height(px(20)).background(.accent).onClick {}
            .position(.absolute).inset(insets(top: dim(10), left: dim(30)))
    }
}

/// Two plain members, so a `.frame` over it is `LR-BH`'s row of per-member frames.
private struct PlainPair: Component {
    var content: some ElementGroup {
        Box().cssWidth(px(10)).cssHeight(px(10)).background(.surface)
        Box().cssWidth(px(10)).cssHeight(px(10)).background(.surface)
    }
}

/// **N1.2** (`LR-EV` items 1–2; record §50 §3, A0/A1). A1 —
/// `Box().frame(width: 20, height: 20).background(.accent).onClick {}
/// .position(.absolute).inset(top 10, left 30)` inside a `Deferred` — lays out at
/// (30, 10) 20×20 with its hitbox there (under **both** authorities until stage
/// 9), and the frame reports nothing; A0, the deprecated own-box spelling, reads
/// the same (its control).
///
/// Red before (`85217e3`'s source): the proposal arm lays the box out at 0×0 and
/// reports `modifierLayer.style` (record §50 §3).
///
/// Mutation that must redden it: **M1a** (the frame layer's `style` comparison
/// restored to the exact one — no absolute exemption) → this test and N1.4.
///
/// **Renamed at stage 9** from `aFramedAbsoluteBoxIsAPresentationRootUnderBothAuthorities`
/// (`LR-FE` item 6).
@MainActor
@Test func aFramedAbsoluteBoxIsAPresentationRoot() throws {
    let expected = pBounds(30, 10, 20, 20)
    let box = pChild(pChild(pChild(pRoot, 0), 0), 0)
    func check<E: Element>(_ name: String, _ make: @escaping @MainActor () -> E) {
        let report = LayoutDifferential.report(width: 200, height: 200) {
            Box { Deferred { make() } }.alignItems(.flexStart)
        }
        expectNothingReported(report, name)
        #expect(report.bounds[box] == expected, "\(name): lowered \(String(describing: report.bounds[box]))")
        let hits = report.frame.hitboxes.filter { $0.id == box }
        #expect(hits.count == 1 && hits.first?.bounds == expected, "\(name): hitboxes \(hits.map(\.bounds))")
    }
    check("A1, .frame before .position") {
        Box().frame(width: px(20), height: px(20)).background(.accent).onClick {}
            .position(.absolute).inset(insets(top: dim(10), left: dim(30)))
    }
    check("A0, the deprecated own-box size (control)") { oldSpelling(FramedAbsoluteOldSpelling()) }
}

/// **N1.3** (`LR-EV` item 2; probe `swiftui-engine-stage-8.swift` P0–P2). A
/// frame's own bounds on an absolute box's `auto` axis answer as SwiftUI's frame
/// does, under the proposal authority: `Box { Text("hi") }.frame(minWidth: 100)`
/// is **100×16**, `.frame(maxWidth: 80)` is **80×16** (the text is 11 wide, so the
/// maximum is greedy up to the window-minus-inset proposal, P2), and neither
/// reports. The control arm (no frame) is **11×16** — so each arm's width is the
/// frame's doing. A **proposal-only** answer: the legacy engine ignores an
/// auto-axis bound on an absolute box (`AP-E`), unnumbered by `LR-CJ`'s precedent.
///
/// Red before: each framed arm reports `modifierLayer.style`.
///
/// Mutation that must redden it: **M1b** (`lowerPresentation`'s `…absolute`
/// check no longer skips a `.frameLayer` record) → this test, reporting
/// `modifierLayer.minSize.absolute` / `.maxSize.absolute`.
@MainActor
@Test func aFramesOwnBoundsOnAnAbsoluteAutoAxisAnswerAsSwiftUIsFrameDoes() throws {
    let box = pChild(pChild(pChild(pRoot, 0), 0), 0)
    func arm<E: Element>(_ name: String, _ make: @escaping @MainActor () -> E) -> (Bounds<Pixels>?, [String]) {
        let frame = LayoutDifferential.render(width: 200, height: 200) {
            Box { Deferred { make() } }.alignItems(.flexStart)
        }
        return (frame.elementBounds[box], frame.unlowerableFields.map(\.description))
    }
    let control = arm("control, no frame") {
        Box { Text("hi") }.background(.accent).position(.absolute).inset(insets(top: dim(10), left: dim(30)))
    }
    let minimum = arm("minWidth 100") {
        Box { Text("hi") }.frame(minWidth: px(100)).background(.accent)
            .position(.absolute).inset(insets(top: dim(10), left: dim(30)))
    }
    let maximum = arm("maxWidth 80") {
        Box { Text("hi") }.frame(maxWidth: px(80)).background(.accent)
            .position(.absolute).inset(insets(top: dim(10), left: dim(30)))
    }
    try #require(control.0 == pBounds(30, 10, 11, 16) && control.1.isEmpty,
                 "control: \(String(describing: control.0)) \(control.1)")
    #expect(minimum.0 == pBounds(30, 10, 100, 16) && minimum.1.isEmpty,
            "minWidth 100: \(String(describing: minimum.0)) \(minimum.1)")
    #expect(maximum.0 == pBounds(30, 10, 80, 16) && maximum.1.isEmpty,
            "maxWidth 80: \(String(describing: maximum.0)) \(maximum.1)")
}

/// **N1.4** (`LR-EV` items 1 and 3, as amended by `LR-EY` item 3). The
/// exemption covers `position` and `inset` on a frame over at most one node, and
/// nothing else:
///
/// 1. `.frame(20×20).position(.absolute).inset(…).flexGrow(1)` in a `Deferred`
///    still reports `modifierLayer.style` — the grow is a caller's modifier on
///    the frame's own layer;
/// 2. `.frame(20×20).position(.absolute).inset(…)` in a `Column`, no `Deferred`,
///    reports `modifierLayer.position` then `modifierLayer.inset` — removed from
///    the proposal authority as any absolute box outside a `Deferred` is
///    (`LR-CK`), not lowered in flow;
/// 3. a two-member `Component`'s `.frame(width: 20, height: 20).position(.absolute)
///    .inset(…)` in a `Deferred` still reports `modifierLayer.style` — a row of
///    per-member frames as a presentation root is unmeasured (owner stage 11).
/// 4. the same framed absolute box **as the frame's root** reports
///    `modifierLayer.position.unconsumed` then `modifierLayer.inset.unconsumed`, as
///    the own-box spelling reports `box.position.unconsumed`/`box.inset.unconsumed`
///    there — an unconsumed frame-layer record
///    whose declared style is absolute reports those two names and only those
///    (`LR-FA`), so a converted absolute root still traps in production.
///
/// Red before: arm 2 reports `[modifierLayer.style]`; arm 4 reported `[]` until
/// `LR-FA` (lane 1's review round).
///
/// Mutations that must redden it: **M1c** (the comparison skipped entirely when
/// the declared style is absolute) → arm 1; **M1d** (the `.frameLayer` guard
/// restored in `planLegacyItems`' outside-a-`Deferred` report) → arm 2 lowers
/// silently; **M1h** (the one-node condition dropped from the exemption) → arm 3;
/// **M1i** (`reportUnconsumedLoweredItems`' unconditional `.frameLayer` skip
/// restored) → arm 4 lowers silently.
@MainActor
@Test func aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred() throws {
    let grown = rootDiagnostics(width: 200, height: 200) {
        Box {
            Deferred {
                Box().frame(width: px(20), height: px(20)).background(.accent)
                    .position(.absolute).inset(insets(top: dim(10), left: dim(30))).flexGrow(1)
            }
        }
    }
    let inFlow = rootDiagnostics(width: 200, height: 200) {
        Column {
            Box().frame(width: px(20), height: px(20)).background(.accent)
                .position(.absolute).inset(insets(top: dim(10), left: dim(30)))
        }
    }
    let pair = rootDiagnostics(width: 200, height: 200) {
        Box {
            Deferred {
                PlainPair().frame(width: px(20), height: px(20))
                    .position(.absolute).inset(insets(top: dim(10), left: dim(30)))
            }
        }
    }
    #expect(grown == ["modifierLayer.style"], "arm 1, a grow after the frame: \(grown)")
    #expect(inFlow == ["modifierLayer.position", "modifierLayer.inset"], "arm 2, no Deferred: \(inFlow)")
    #expect(pair == ["modifierLayer.style"], "arm 3, a two-member frame: \(pair)")
    let asRoot = rootDiagnostics(width: 200, height: 200) {
        Box().frame(width: px(20), height: px(20)).background(.accent)
            .position(.absolute).inset(insets(top: dim(10), left: dim(30)))
    }
    #expect(asRoot == ["modifierLayer.position.unconsumed", "modifierLayer.inset.unconsumed"], "arm 4, the frame's root: \(asRoot)")
}
