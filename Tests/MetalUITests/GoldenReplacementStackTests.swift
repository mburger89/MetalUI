import Foundation
import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 7a, lane 2 (`docs/superpowers/specs/2026-09-23-engine-stage-7a-design.md`
// §5 and §6 lane 2; rulings LR-DS, LR-DV, LR-DW, LR-DY): the stack and absolute **R**
// goldens, the seven silent **D** shapes, and `wrap-reverse`'s report, retired.
//
// Tests 2.1–2.4 are R arms: each builds its golden's own tree — the fixture's CSS as
// `Box(style:)` fields, transcribed exactly as the design's instrument
// (`docs/probes/stage-7a-transcription-instrument.patch`) wrote it, a CSS grid with
// `grid-area: 1/1` as `display: .stack`, an absolute box inside a `Deferred` with the
// window sized to the fixture's `position: relative` root — and asserts, under the
// **proposal** authority, the golden's `rounded` boxes (record §48 §5.1) exactly,
// with an empty report, through lane 1's `goldenArm` (reused, never copied).
//
// Tests 2.5–2.7 are D pins (`LR-DV`): the golden's own tree, asserting the **native**
// answer (record §48 §5.2), which deliberately differs from WebKit's. Each doc comment
// names the golden, WebKit's answer, the native answer and the deleted CSS concept, so
// a reader who sees the native number knows it is a divergence and not a regression.
// What is deleted is the golden's CSS **answer**, not the field (`LR-DY` item 3).
//
// Test 2.8 (`LR-DY`) pins the report of the three `wrap-reverse` goldens' own trees.
//
// **Characterization** (`LR-DW`): every test is green on arrival; its red-before is
// the mutation named in its doc comment (spec §6's lane-2 table), applied to the
// committed source and run in the full unfiltered suite; record §48 §6.2 names every
// test and arm each mutation reddened.

// MARK: - 2.1–2.4, R arms

/// A stack (`display: .stack`) places a fixed child at its `justifyItems` ×
/// `alignItems` alignment. **M2a** (`alignmentFactor(_: JustifyItems?)`: `.end` →
/// 0.5) reddens `stack_alignment_bottomtrailing` (child x 280 → 140).
@MainActor
@Test func aStackPlacesAFixedChildAtItsAlignment() throws {
    let arms = [("stack_alignment_center", JustifyItems.center, AlignItems.center,
                 "root:0,0,300x200 child:140,95,20x10"),
                ("stack_alignment_topleading", .start, .flexStart,
                 "root:0,0,300x200 child:0,0,20x10"),
                ("stack_alignment_bottomtrailing", .end, .flexEnd,
                 "root:0,0,300x200 child:280,190,20x10")]
    try #require(arms.count == 3)
    for (golden, justify, align, boxes) in arms {
        try goldenArm(golden, boxes) {
            gBox("root", { gSize(&$0, 300, 200); $0.display = .stack; $0.justifyItems = justify; $0.alignItems = align }) {
                gLeaf("child") { gSize(&$0, 20, 10) }
            }
        }
    }
}

/// A stretched stack child fills only its `auto` axes, clamped by its own minimum
/// and maximum. `stack_stretch_max` is the golden's tree **minus `p`**, its
/// percentage-maximum child (percentages are D, `LR-DU`; the whole tree reports
/// `box.maxSize.percent`, record §48 §2): the arm asserts root, `h` and `w`.
/// **M2b** (`planLegacyItems`, the `.stack` case: `&& d.size.width == .auto`
/// dropped) reddens `stack_stretch_declared_size` (child 300 wide).
@MainActor
@Test func aStretchedStackChildFillsOnlyItsAutoAxesWithinItsOwnBounds() throws {
    func stretching(_ s: inout Style) {
        gSize(&s, 300, 200); s.display = .stack; s.justifyItems = .stretch; s.alignItems = .stretch
    }
    try goldenArm("stack_stretch", "root:0,0,300x200 child:0,0,300x200") {
        gBox("root", stretching) { gLeaf("child") { _ in } }
    }
    try goldenArm("stack_stretch_declared_size", "root:0,0,300x200 child:0,0,20x10") {
        gBox("root", stretching) { gLeaf("child") { gSize(&$0, 20, 10) } }
    }
    try goldenArm("stack_stretch_min", "root:0,0,300x200 m:0,0,340x260") {
        gBox("root", stretching) { gLeaf("m") { $0.minSize = Size(width: gPx(340), height: gPx(260)) } }
    }
    try goldenArm("stack_stretch_max", "root:0,0,300x200 h:0,0,300x50 w:0,0,40x200") {
        gBox("root", stretching) {
            gLeaf("h") { $0.maxSize = Size(width: .auto, height: gPx(50)) }
            gLeaf("w") { $0.maxSize = Size(width: gPx(40), height: .auto) }
        }
    }
}

/// A stack hugs its largest child on each axis, centring the others, both as a
/// row's child and around a row. **M2c** (`LayoutTree`'s `.overlay` measurement
/// answers its first child's size) reddens `stack_sizes_to_largest` and
/// `stack_in_flex` (stack 50×40).
@MainActor
@Test func aStackHugsItsLargestChildInsideARowAndAroundOne() throws {
    try goldenArm("stack_sizes_to_largest",
                  "root:0,0,400x300 stack:0,0,90x70 mid:20,15,50x40 wide:0,30,90x10 tall:35,0,20x70") {
        gBox("root", { gSize(&$0, 400, 300); $0.alignItems = .flexStart }) {
            gBox("stack", { $0.display = .stack; $0.justifyItems = .center; $0.alignItems = .center }) {
                gLeaf("mid") { gSize(&$0, 50, 40) }; gLeaf("wide") { gSize(&$0, 90, 10) }; gLeaf("tall") { gSize(&$0, 20, 70) }
            }
        }
    }
    try goldenArm("stack_in_flex",
                  "root:0,0,400x150 before:0,0,40x30 stack:40,0,90x70 mid:60,15,50x40 wide:40,30,90x10 tall:75,0,20x70 after:130,0,60x20") {
        gBox("root", { gSize(&$0, 400, 150); $0.alignItems = .flexStart }) {
            gLeaf("before") { gSize(&$0, 40, 30) }
            gBox("stack", { $0.display = .stack; $0.justifyItems = .center; $0.alignItems = .center }) {
                gLeaf("mid") { gSize(&$0, 50, 40) }; gLeaf("wide") { gSize(&$0, 90, 10) }; gLeaf("tall") { gSize(&$0, 20, 70) }
            }
            gLeaf("after") { gSize(&$0, 60, 20) }
        }
    }
    try goldenArm("flex_in_stack",
                  "root:0,0,300x200 backdrop:50,40,200x120 row:105,88,90x25 item0:105,88,30x25 item1:135,88,30x25 item2:165,88,30x25") {
        gBox("root", { gSize(&$0, 300, 200); $0.display = .stack; $0.justifyItems = .center; $0.alignItems = .center }) {
            gLeaf("backdrop") { gSize(&$0, 200, 120) }
            gBox("row", { _ in }) {
                gLeaf("item0") { gSize(&$0, 30, 25) }; gLeaf("item1") { gSize(&$0, 30, 25) }; gLeaf("item2") { gSize(&$0, 30, 25) }
            }
        }
    }
}

/// An absolute box inside a `Deferred` resolves its insets — px and percent, each
/// percentage against its own axis of the window — against the window, which here
/// stands for the fixture's `position: relative` root, skips every static ancestor
/// (the padded root, the wrapper) and takes no space in the flow.
/// **M2d** (`lowerPresentation`: the vertical axis resolved against
/// `window.width`) reddens `abs_percent_insets_nonsquare` (abs y 10 → 20).
@MainActor
@Test func aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow() throws {
    func pc(_ f: Float) -> MetalUICore.Dimension { .length(.percent(f)) }
    try goldenArm("abs_containing_block_skips_static", window: (200, 100),
                  "root:0,0,200x100 abs:0,0,20x10") {
        gBox("root", { gSize(&$0, 200, 100); $0.padding = Edges(all: gPl(5)) }) {
            gBox("wrapper", { _ in }) {
                gLeaf("spacer") { gSize(&$0, 60, 10) }
                Deferred {
                    gLeaf("abs") {
                        $0.position = .absolute
                        $0.inset = Edges(top: gPx(0), right: .auto, bottom: .auto, left: gPx(0))
                        gSize(&$0, 20, 10)
                    }
                }
            }
        }
    }
    try goldenArm("abs_percent_insets_nonsquare", window: (200, 100),
                  "root:0,0,200x100 abs:20,10,20x10") {
        gBox("root", { gSize(&$0, 200, 100) }) {
            Deferred {
                gLeaf("abs") {
                    $0.position = .absolute
                    $0.inset = Edges(top: pc(0.1), right: .auto, bottom: .auto, left: pc(0.1))
                    gSize(&$0, 20, 10)
                }
            }
        }
    }
    try goldenArm("abs_over_constrained", window: (200, 100),
                  "root:0,0,200x100 abs:40,10,50x70") {
        gBox("root", { gSize(&$0, 200, 100) }) {
            Deferred {
                gLeaf("abs") { $0.position = .absolute; $0.inset = gMargin(10, 30, 20, 40); gSize(&$0, 50, nil) }
            }
        }
    }
    try goldenArm("abs_single_inset_auto_size", window: (200, 100),
                  "root:0,0,200x100 abs:20,10,35x15 content:20,10,35x15") {
        gBox("root", { gSize(&$0, 200, 100) }) {
            Deferred {
                gBox("abs", { $0.position = .absolute; $0.inset = Edges(top: gPx(10), right: .auto, bottom: .auto, left: gPx(20)) }) {
                    gLeaf("content") { gSize(&$0, 35, 15) }
                }
            }
        }
    }
    try goldenArm("abs_removed_from_flow",
                  "root:0,0,400x300 container:0,0,40x20 inflow:0,0,40x20 abs:0,0,500x300") {
        gBox("root", { gSize(&$0, 400, 300); $0.flexDirection = .column; $0.alignItems = .flexStart }) {
            gBox("container", { _ in }) {
                gLeaf("inflow") { gSize(&$0, 40, 20) }
                Deferred { gLeaf("abs") { $0.position = .absolute; gSize(&$0, 500, 300) } }
            }
        }
    }
}

// MARK: - 2.5–2.7, D pins

/// **D pin.** Deleted concept: the **sub-one grow sum** (flex §9.7.4.b: when the
/// grow factors sum below 1, each item takes only its factor's fraction of the free
/// space). SwiftUI shares the line equally (7a probe G0); the lowering does the same.
///
/// - `flex_row_fractional_grow` (three `flex: 0.25 1 0` in 400): WebKit a 100, b 100
///   at 100, c 100 at 200 (100 left unused); native a 133, b 134 at 133, c 133 at 267.
/// - `flex_row_fractional_grow_clamped` (a `max-width: 50`, b, both 0.25): WebKit a 50,
///   b 100 at 50; native a 50, b **350** at 50.
///
/// **M2e** (`planLegacyItems`: `d.flexGrow > 0` → `d.flexGrow >= 1` for
/// `grownH`/`grownV`) reddens both arms.
@MainActor
@Test func aGrowFactorSumBelowOneStillFillsTheLine() throws {
    try goldenArm("flex_row_fractional_grow",
                  "root:0,0,400x40 a:0,0,133x40 b:133,0,134x40 c:267,0,133x40") {
        gBox("root", { gSize(&$0, 400, 40) }) {
            gLeaf("a") { gFlex(&$0, 0.25, 1, gPx(0)) }
            gLeaf("b") { gFlex(&$0, 0.25, 1, gPx(0)) }
            gLeaf("c") { gFlex(&$0, 0.25, 1, gPx(0)) }
        }
    }
    try goldenArm("flex_row_fractional_grow_clamped",
                  "root:0,0,400x40 a:0,0,50x40 b:50,0,350x40") {
        gBox("root", { gSize(&$0, 400, 40) }) {
            gLeaf("a") { gFlex(&$0, 0.25, 1, gPx(0)); $0.maxSize = Size(width: gPx(50), height: .auto) }
            gLeaf("b") { gFlex(&$0, 0.25, 1, gPx(0)) }
        }
    }
}

/// **D pin.** Deleted concept: the **border-box floor** (`BM-4`: padding + border
/// floor a stretched size, even past the item's maximum). 7a probe B1 vs B0: a
/// SwiftUI frame keeps its size under padding that exceeds it.
///
/// `stack_stretch_border_box_floor` (a 100×100 stretching stack; `f` and `c` each
/// padded 60/50/60/50 with a 10 border, `c` also `max` 40×50): WebKit f 120×140 and
/// c 120×140; native f 100×100 (the stack's own size) and c 40×50 (its maximum).
///
/// **M2f** (`planLegacyItems.axis`, the stretched axis of a non-frame-layer item:
/// `lo` = the item's padding + border on that axis) reddens both boxes (120×140).
///
/// **Stage 10** (record §53, lane 1, row T1.14): `Style.border` is deleted
/// (`LR-FM` item 1), so each 10 border is folded into the padding edge by edge
/// (60/50/60/50 + 10 = 70/60/70/60) — the lowering inset every edge by
/// `padding + border`, so the literals are unchanged.
@MainActor
@Test func aStretchedStackChildIsNotFlooredByItsPaddingAndBorder() throws {
    try goldenArm("stack_stretch_border_box_floor",
                  "root:0,0,100x100 f:0,0,100x100 c:0,0,40x50") {
        gBox("root", { gSize(&$0, 100, 100); $0.display = .stack; $0.justifyItems = .stretch; $0.alignItems = .stretch }) {
            gLeaf("f") { $0.padding = gEdges(70, 60, 70, 60) }
            gLeaf("c") {
                $0.padding = gEdges(70, 60, 70, 60)
                $0.maxSize = Size(width: gPx(40), height: gPx(50))
            }
        }
    }
}

/// **D pin.** A declared size is kept: it is not shrunk, not floored by content and
/// not floored by padding + border. Deleted concepts, per arm:
///
/// - `flex_row_shrink_padded_weighting` — **weighted shrink** (flex §9.7: the shrink
///   weight is the inner base size): WebKit a 125, b 75 at 125; native a 200, b 200 at
///   200 (overflow; 7a probe S1 vs S0).
/// - `sizing_specified_suggestion` — **automatic minimum** (flex §4.5's specified
///   size suggestion): WebKit a 130 (g1 130), b shrunk to 20 at 130; native a 130
///   (g1 200), b 100 at 130 (7a probe A1 vs A0).
/// - `sizing_specified_suggestion_is_used_value` — **automatic minimum** and the
///   **border-box floor** (`BM-4`): WebKit a 120 (g1 0×20 at 60,10), b 30 at 120;
///   native a 100 (g1 200×20 at 60,10), b 100 at 100.
/// - `sizing_over_constrained_grows` — the **border-box floor**: WebKit box 120×140,
///   kid 0×10 at 60,70; native box 100×80, kid 10×10 at 60,70 (7a probe B1 vs B0).
///
/// **M2g** (`paddedAndSized`: each folded declared size raised to its padding +
/// border sum) reddens `sizing_over_constrained_grows` (box 120×140) and
/// `sizing_specified_suggestion_is_used_value` (a 120).
///
/// **Stage 10** (record §53, lane 1, row T1.15): `Style.border` is deleted
/// (`LR-FM` item 1), so the two 10 borders are folded into their paddings edge by
/// edge — the lowering inset every edge by `padding + border`, so the literals are
/// unchanged.
@MainActor
@Test func aDeclaredMainSizeIsNeitherShrunkNorFlooredByContentOrPadding() throws {
    try goldenArm("flex_row_shrink_padded_weighting",
                  "root:0,0,200x40 a:0,0,200x40 b:200,0,200x40") {
        gBox("root", { gSize(&$0, 200, 40) }) {
            gLeaf("a") { gSize(&$0, 200, nil); $0.padding = gEdges(0, 40, 0, 40) }
            gLeaf("b") { gSize(&$0, 200, nil) }
        }
    }
    try goldenArm("sizing_specified_suggestion",
                  "root:0,0,150x60 a:0,0,130x60 g1:0,0,200x20 b:130,0,100x20") {
        gBox("root", { gSize(&$0, 150, 60) }) {
            gBox("a", { gSize(&$0, 130, nil) }) { gLeaf("g1") { gSize(&$0, 200, 20) } }
            gLeaf("b") { gSize(&$0, 100, 20) }
        }
    }
    try goldenArm("sizing_specified_suggestion_is_used_value",
                  "root:0,0,150x60 a:0,0,100x60 g1:60,10,200x20 b:100,0,100x20") {
        gBox("root", { gSize(&$0, 150, 60) }) {
            gBox("a", { gSize(&$0, 100, nil); $0.padding = gEdges(10, 60, 10, 60) }) {
                gLeaf("g1") { gSize(&$0, 200, 20) }
            }
            gLeaf("b") { gSize(&$0, 100, 20) }
        }
    }
    try goldenArm("sizing_over_constrained_grows",
                  "root:0,0,400x300 box:0,0,100x80 kid:60,70,10x10") {
        gBox("root", { gSize(&$0, 400, 300) }) {
            gBox("box", { gSize(&$0, 100, 80); $0.padding = gEdges(70, 60, 70, 60) }) {
                gLeaf("kid") { gSize(&$0, 10, 10) }
            }
        }
    }
}

// MARK: - 2.8, wrap-reverse's report (LR-DY) — retired at stage 10

// **D, reported** `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` (`LR-DY`)
// is **retired** at stage 10 (record §53, lane 1, row D1.1). Its deleted concept,
// **wrap** (`flex-wrap`/`align-content`; a SwiftUI stack lays out one line, 7a
// probe W1, W2 vs W0), is now unspellable: `Style.flexWrap`/`alignContent`,
// `FlexWrap`, `AlignContent` and the `flexWrap(_:)`/`alignContent(_:)` modifiers
// are deleted (`LR-FM` item 1, `LR-FN`, lane 2), so the report the test pinned
// cannot be raised. Lane 2's guard G2 pins that neither `flexWrap(_:)` nor
// `FlexWrap` exists.
