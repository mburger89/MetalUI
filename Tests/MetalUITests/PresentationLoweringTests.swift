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
// block is not the window reports by name (`LR-CL`).
//
// **Diagnostics are compared by their printed description** (`"box.position"`),
// not by `UnlowerableField` values, so that this file compiled against the source
// before `LoweringSite.deferred` existed and its red-before could be taken by
// running it (record §28, lane 1).

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
    var root = make()
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)), scaleFactor: 1,
                      layoutAuthority: .proposal, reportsUnlowerableFields: true)
    frame.render(&root)
    return frame.unlowerableFields.map(\.description)
}

/// Every whole-frame observation agrees and nothing was reported.
@MainActor
private func expectAgreement(_ r: LayoutDifferential.Report, _ arm: String,
                             sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
    #expect(r.disagreeing.isEmpty, "\(arm): \(r.disagreeing)", sourceLocation: sourceLocation)
    #expect(r.legacyOnly.isEmpty && r.loweredOnly.isEmpty,
            "\(arm): legacyOnly \(r.legacyOnly) loweredOnly \(r.loweredOnly)", sourceLocation: sourceLocation)
    #expect(r.scenesEqual, "\(arm): scenes", sourceLocation: sourceLocation)
    #expect(r.hitboxesEqual, "\(arm): hitboxes", sourceLocation: sourceLocation)
    #expect(r.accessibilityEqual, "\(arm): accessibility", sourceLocation: sourceLocation)
    #expect(r.stateSlotsEqual, "\(arm): state slots", sourceLocation: sourceLocation)
}

private struct PresentingSolo: Component {
    var content: some ElementGroup {
        Deferred { absBox(insets(top: dim(5), left: dim(5))).width(px(10)).height(px(10)) }
    }
}

private struct PresentingPair: Component {
    var content: some ElementGroup {
        Box().width(px(10)).height(px(10)).background(.surface)
        Deferred { absBox(insets(top: dim(5), left: dim(5))).width(px(10)).height(px(10)) }
    }
}

// MARK: - 1.1 The placement, per inset shape

/// **1.1** (`LR-CI`). `LayoutDifferential.compare` at **200×100** — non-square on
/// purpose, so a width/height basis swap for a percentage is visible (`AP-D`) —
/// one arm per shape of spec §2.4 that lowers. Each arm puts `Box { Deferred {
/// absolute box } }` under the harness root, so the `Deferred` is received by a
/// lowered container (which drops its placeholder) and the harness root's native
/// node is the window. Each: no report, every observation equal, and the box's and
/// the `Deferred`'s rect equal to the legacy engine's measured answer.
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
        arms.append((name, LayoutDifferential.compare(width: 200, height: 100, make), deferredIndex, expected))
    }
    arm("top/left px", pBounds(5, 5, 30, 20)) {
        Box { Deferred { absBox(insets(top: dim(5), left: dim(5))).width(px(30)).height(px(20)) } }
    }
    arm("right/bottom px, declared size", pBounds(163, 71, 30, 20)) {
        Box { Deferred { absBox(insets(right: dim(7), bottom: dim(9))).width(px(30)).height(px(20)) } }
    }
    arm("all four, auto size (stretched on both axes)", pBounds(40, 10, 140, 60)) {
        Box { Deferred { absBox(insets(top: dim(10), right: dim(20), bottom: dim(30), left: dim(40))) } }
    }
    arm("left/right, auto width, declared height", pBounds(10, 0, 160, 20)) {
        Box { Deferred { absBox(insets(right: dim(30), left: dim(10))).height(px(20)) } }
    }
    arm("all four, declared size (the leading insets win)", pBounds(40, 10, 30, 20)) {
        Box {
            Deferred {
                absBox(insets(top: dim(10), right: dim(20), bottom: dim(30), left: dim(40)))
                    .width(px(30)).height(px(20))
            }
        }
    }
    // Divergence 9, on both authorities: no inset puts the box at the containing
    // block's origin, not at CSS's static position after the in-flow sibling.
    arm("no insets, after an in-flow sibling (divergence 9)", deferredIndex: 1, pBounds(0, 0, 30, 20)) {
        Box {
            Box().width(px(40)).height(px(20)).background(.surface)
            Deferred { absBox(insets()).width(px(30)).height(px(20)) }
        }
    }
    arm("percent: top against the height, left against the width", pBounds(50, 50, 10, 10)) {
        Box {
            Deferred {
                absBox(insets(top: .length(.percent(0.5)), left: .length(.percent(0.25))))
                    .width(px(10)).height(px(10))
            }
        }
    }
    arm("rem", pBounds(32, 16, 10, 10)) {
        Box {
            Deferred {
                absBox(insets(top: .length(.rems(Rems(1))), left: .length(.rems(Rems(2)))))
                    .width(px(10)).height(px(10))
            }
        }
    }
    arm("declared width 40, minWidth 50 (clamped on a declared axis, AP-E)", pBounds(5, 5, 50, 10)) {
        Box {
            Deferred {
                absBox(insets(top: dim(5), left: dim(5))).width(px(40)).minWidth(px(50)).height(px(10))
            }
        }
    }
    arm("margin, flexGrow and alignSelf present (dropped, as the legacy engine ignores them)",
        pBounds(5, 5, 30, 20)) {
        Box {
            Deferred {
                absBox(insets(top: dim(5), left: dim(5))).width(px(30)).height(px(20))
                    .margin(px(7)).flexGrow(1).alignSelf(.center)
            }
        }
    }
    try #require(arms.count == 10)
    for arm in arms {
        expectAgreement(arm.report, arm.name)
        let deferred = pChild(pChild(pRoot, 0), arm.deferredIndex), box = pChild(deferred, 0)
        #expect(arm.report.legacyBounds[box] == arm.expected, "\(arm.name): legacy box \(String(describing: arm.report.legacyBounds[box]))")
        #expect(arm.report.loweredBounds[box] == arm.expected, "\(arm.name): lowered box \(String(describing: arm.report.loweredBounds[box]))")
        #expect(arm.report.legacyBounds[deferred] == arm.expected, "\(arm.name): legacy Deferred \(String(describing: arm.report.legacyBounds[deferred]))")
        #expect(arm.report.loweredBounds[deferred] == arm.expected, "\(arm.name): lowered Deferred \(String(describing: arm.report.loweredBounds[deferred]))")
    }
}

// MARK: - 1.2, 1.3 The two deliberate proposal-only answers (`LR-CJ`)

/// **1.2** (`LR-CJ` item 2). A box stretched between insets leaving 10×10, with
/// padding 10 on every edge: the legacy engine floors the border box at the
/// padding sum (`BM-4`) — **20×20** at (100, 10); the lowering keeps the inset box
/// — **10×10** at (100, 10) — and lets the padding overflow, `LR-AH`/`LR-AW`'s
/// answer applied to the third place the question arises. Pinned by name, both
/// literals.
///
/// Red-before: reports `[box.position, box.inset]`.
///
/// Mutation that must redden it: **M1e** W's minimum set to the padding + border
/// sum (lowered reads 20×20).
@MainActor
@Test func anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBoxWhereTheLegacyEngineFloorsIt() throws {
    var padded = Style()
    padded.padding = Edges(all: .pixels(px(10)))
    let report = LayoutDifferential.compare(width: 200, height: 100) {
        Box {
            Deferred {
                Box(style: padded).background(.accent)
                    .position(.absolute).inset(insets(top: dim(10), right: dim(90), bottom: dim(80), left: dim(100)))
            }
        }
    }
    #expect(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let box = pChild(pChild(pChild(pRoot, 0), 0), 0)
    #expect(report.legacyBounds[box] == pBounds(100, 10, 20, 20), "legacy \(String(describing: report.legacyBounds[box]))")
    #expect(report.loweredBounds[box] == pBounds(100, 10, 10, 10), "lowered \(String(describing: report.loweredBounds[box]))")
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
@MainActor
@Test func anAbsoluteTextWrapsAtTheWindowMinusItsInsetWhereTheLegacyEngineWrapsAtTheWindow() throws {
    let sentence = "The quick brown fox jumps over the lazy dog and it goes on"
    try #require(sentence.count == 58)
    let report = LayoutDifferential.compare(width: 200, height: 200) {
        Box { Deferred { Text(sentence).position(.absolute).inset(insets(left: dim(150))) } }
    }
    #expect(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let text = pChild(pChild(pChild(pRoot, 0), 0), 0)
    let legacy = try #require(report.legacyBounds[text]), lowered = try #require(report.loweredBounds[text])
    #expect(legacy == pBounds(150, 0, 196, 32), "legacy \(legacy)")
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
/// per-member row, `LR-BH`). Each: no report and every observation equal.
///
/// Red-before: every arm reports `[box.position, box.inset]`.
///
/// Mutations that must redden it: **M1g** the filter removed from
/// `lowerLegacyNode` (the column, stack, scroll and `.padding` arms); **M1h**
/// removed from `lowerLegacyLayer`'s frame arm only (the two `.frame` arms);
/// **M1o** the frame arm's `legacyFrameLayerDiagnostics` handed the **dropped**
/// count (both `.frame` arms report `[modifierLayer.style]`).
@MainActor
@Test func aPresentationPlaceholderIsDroppedByEveryLoweredContainer() throws {
    func presented() -> Deferred<Box<EmptyGroup>> {
        Deferred { absBox(insets(top: dim(5), left: dim(5))).width(px(10)).height(px(10)) }
    }
    let column = LayoutDifferential.compare(width: 200, height: 100) {
        Column(gap: px(12)) {
            Box().width(px(10)).height(px(10)).background(.surface)
            presented()
            Box().width(px(11)).height(px(10)).background(.surface)
        }
    }
    expectAgreement(column, "gapped column")
    let third = pChild(pChild(pRoot, 0), 2)
    #expect(column.legacyBounds[third]?.origin.y == px(22) && column.loweredBounds[third]?.origin.y == px(22),
            "the column's third child: \(String(describing: column.legacyBounds[third])) / \(String(describing: column.loweredBounds[third]))")
    let stack = LayoutDifferential.compare(width: 200, height: 100) {
        Stack {
            Box().width(px(10)).height(px(10)).background(.surface)
            presented()
        }
    }
    expectAgreement(stack, "Stack")
    let scroll = LayoutDifferential.compare(width: 200, height: 100) {
        Box {
            ScrollView(.vertical) {
                presented()
                ProbeLeaf(width: 80, height: 200)
            }
        }
        .width(px(80)).height(px(60))
    }
    expectAgreement(scroll, "ScrollView content")
    let wrap = LayoutDifferential.compare(width: 200, height: 100) {
        Box { PresentingSolo().padding(px(4)) }
    }
    expectAgreement(wrap, "Component .padding (the wrap op)")
    let oneNodeFrame = LayoutDifferential.compare(width: 200, height: 100) {
        Box { PresentingSolo().frame(width: px(50), height: px(50)) }
    }
    expectAgreement(oneNodeFrame, "one-node .frame layer")
    let twoMemberFrame = LayoutDifferential.compare(width: 200, height: 100) {
        Box { PresentingPair().frame(width: px(50), height: px(50)) }
    }
    expectAgreement(twoMemberFrame, "two-member .frame layer")
    // Non-vacuity: every arm's absolute box really was laid out against the window.
    for (name, report, deferred) in [
        ("gapped column", column, pChild(pChild(pRoot, 0), 1)),
        ("Stack", stack, pChild(pChild(pRoot, 0), 1)),
    ] {
        #expect(report.loweredBounds[pChild(deferred, 0)] == pBounds(5, 5, 10, 10),
                "\(name): \(String(describing: report.loweredBounds[pChild(deferred, 0)]))")
    }
}

// MARK: - 1.5, 1.6 The containing block, reported by name (`LR-CL`)

/// **1.5** (`LR-CL`, `LR-CK`, `LR-CJ` item 3; `LR-CP` item 2). A plain `Frame`
/// under the proposal authority with diagnostics, the tree **as the root**; each
/// arm's report exactly. The containing block is the window by construction, and
/// every tree whose legacy containing block is not reports:
///
/// - a bordered root, a root declaring width 100 in a 200 window, a root
///   `.frame(maxWidth: 100)` and a root `.frame(minWidth: 300)` →
///   `deferred.containingBlock` (the last two measured at (85, 85) and (285, 85)
///   in the legacy engine against (185, 85) for `.frame(maxWidth: 300)`, the
///   separating arm, which reports nothing);
/// - a `Deferred` root → `deferred.root`;
/// - a presentation inside a top/left-5 presentation → `deferred.nested`; inside
///   an `inset(0)` one → nothing (its padding box is the window);
/// - inside a `.relative` ancestor → the ancestor's own `box.position`;
/// - an absolute box in a column with no `Deferred` → `[box.position, box.inset]`
///   at the consumer; an absolute root → the `.unconsumed` pair;
/// - `minWidth` on an absolute box's `auto` axis → `box.minSize.absolute`;
/// - `Component().width(70)` over a `Deferred`-absolute member → `deferred.amended`.
///
/// Red-before: every `Deferred` arm reads `[box.position, box.inset]`; the
/// absolute-root arm reads `[box.position, box.inset]`.
///
/// Mutations that must redden it: **M1i** the containing-block check deleted
/// (border, width-100 arms); **M1j** the nested check deleted; **M1k**
/// `coversWindow` always false (the `inset(0)` arm reads `[deferred.nested]`);
/// **M1l** `planLegacyItems`' `position` entry deleted (the column arm reads
/// `[box.inset]`); **M1p** the check's `minSize`/`maxSize` clause deleted (the two
/// clamped-frame arms read `[]`).
@MainActor
@Test func aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName() throws {
    func presented() -> Deferred<Box<EmptyGroup>> {
        Deferred { absBox(insets(right: dim(5), bottom: dim(5))).width(px(10)).height(px(10)) }
    }
    var bordered = Style()
    bordered.border = Edges(all: .pixels(px(4)))
    typealias Arm = (name: String, got: [String], expected: [String])
    var arms: [Arm] = []
    arms.append(("bordered root", rootDiagnostics { Box(style: bordered) { presented() } },
                 ["deferred.containingBlock"]))
    arms.append(("root width 100 in 200", rootDiagnostics { Box { presented() }.width(px(100)) },
                 ["deferred.containingBlock"]))
    arms.append(("root width 200", rootDiagnostics { Box { presented() }.width(px(200)) }, []))
    arms.append(("auto root", rootDiagnostics { Box { presented() } }, []))
    arms.append(("Deferred root", rootDiagnostics { presented() }, ["deferred.root"]))
    arms.append(("inside a top/left-5 presentation", rootDiagnostics {
        Box {
            Deferred {
                Box { presented() }.background(.surface).position(.absolute)
                    .inset(insets(top: dim(5), left: dim(5)))
            }
        }
    }, ["deferred.nested"]))
    arms.append(("inside an inset(0) presentation", rootDiagnostics {
        Box { Deferred { Box { presented() }.background(.surface).position(.absolute).inset(px(0)) } }
    }, []))
    arms.append(("inside a .relative ancestor", rootDiagnostics {
        Box { Box { presented() }.position(.relative) }
    }, ["box.position"]))
    arms.append(("absolute in a column, no Deferred", rootDiagnostics {
        Column { absBox(insets(top: dim(5), left: dim(5))).width(px(10)).height(px(10)) }
    }, ["box.position", "box.inset"]))
    arms.append(("absolute root", rootDiagnostics {
        absBox(insets(top: dim(5), left: dim(5))).width(px(10)).height(px(10))
    }, ["box.position.unconsumed", "box.inset.unconsumed"]))
    arms.append(("minWidth on an auto axis", rootDiagnostics {
        Box { Deferred { absBox(insets(top: dim(5), left: dim(5))).height(px(10)).minWidth(px(50)) } }
    }, ["box.minSize.absolute"]))
    arms.append(("Component amend over a presentation member", rootDiagnostics {
        Box { PresentingSolo().width(px(70)) }
    }, ["deferred.amended"]))
    arms.append(("root .frame(maxWidth: 100)", rootDiagnostics {
        Box { presented() }.frame(maxWidth: px(100))
    }, ["deferred.containingBlock"]))
    arms.append(("root .frame(minWidth: 300)", rootDiagnostics {
        Box { presented() }.frame(minWidth: px(300))
    }, ["deferred.containingBlock"]))
    arms.append(("root .frame(maxWidth: 300) (the separating arm)", rootDiagnostics {
        Box { presented() }.frame(maxWidth: px(300))
    }, []))
    try #require(arms.count == 15)
    for arm in arms {
        #expect(arm.got == arm.expected, "\(arm.name): \(arm.got)")
    }
}

/// **1.6** (`LR-CL`; exit test). In a production frame — diagnostics off — a
/// presentation whose containing block is not the window traps, naming its field
/// and **stage 9**, the stage that deletes the legacy authority and with it the
/// answer the report protects.
///
/// Red-before: the child traps on `box.position … stage 2`.
///
/// Mutation that must redden it: **M1m** `owningStage` for `.deferred` → "5".
@Test func aPresentationTrapsAProductionProposalFrameNamingItsField() async throws {
    let child = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var bordered = Style()
            bordered.border = Edges(all: .pixels(Pixels(4)))
            var root = Box(style: bordered) {
                Deferred {
                    Box().width(Pixels(10)).height(Pixels(10)).position(.absolute)
                        .inset(Edges(top: .length(.pixels(Pixels(5))), right: .auto, bottom: .auto,
                                     left: .length(.pixels(Pixels(5)))))
                }
            }
            Frame(contentSize: Size(width: Pixels(200), height: Pixels(100)), scaleFactor: 1,
                  layoutAuthority: .proposal).render(&root)
        }
    }
    let stderr = String(decoding: child?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("MetalUI: deferred.containingBlock has no proposal lowering (plan task 7, stage 9)"),
            "aborted, but not at the containing-block check:\n\(stderr)")
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
                          layoutAuthority: .proposal, reportsUnlowerableFields: true, recordsElementBounds: true)
        frame.render(&root)
        return frame
    }
    let with = frame {
        Box {
            ProbeLeaf(width: 20, height: 10)
            ProbeLeaf(width: 30, height: 10)
            Deferred { absBox(insets(top: dim(5), left: dim(5))).width(px(10)).height(px(10)) }
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
