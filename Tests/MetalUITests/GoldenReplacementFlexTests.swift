import Foundation
import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 7a, lane 1 (`docs/superpowers/specs/2026-09-23-engine-stage-7a-design.md`
// §5 and §6 lane 1; rulings LR-DS, LR-DW): the flex **R** goldens, retired. Each arm
// is labelled by the WebKit golden it replaces (record §48 §4), builds that golden's
// own tree — its fixture's CSS as `Box(style:)` fields, transcribed exactly as the
// design's instrument (`docs/probes/stage-7a-transcription-instrument.patch`) wrote
// it, the instrument having shown the **legacy** authority reproduces every one of
// these goldens on these trees — and asserts, under the **proposal** authority, the
// golden's `rounded` boxes (record §48 §5.1) exactly, with an empty report.
//
// **Characterization** (`LR-DW`): the behaviour exists, so every test is green on
// arrival. Its red-before is the mutation named in its doc comment (spec §6's
// lane-1 table), applied to the committed source and run in the full unfiltered
// suite; record §48 §6 names every test and arm each mutation reddened.
//
// The trees use `Style` fields stages 8 and 10 respell or delete; these are lowering
// tests and go with the lowering suites (spec §9).

/// Fixed items pack from the main start at their own sizes; a main-axis gap
/// separates each pair. **M1a** (`arrangeLegacyMainAxis`: `var spacing = gap` →
/// `0`) reddens `flex_row_gap`.
@MainActor
@Test func fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap() throws {
    try goldenArm("flex_row_three_fixed",
                  "root:0,0,300x50 x:0,0,60x20 y:60,0,90x30 z:150,0,40x50") {
        gBox("root", { gSize(&$0, 300, 50) }) {
            gLeaf("x") { gSize(&$0, 60, 20) }; gLeaf("y") { gSize(&$0, 90, 30) }; gLeaf("z") { gSize(&$0, 40, 50) }
        }
    }
    try goldenArm("flex_column_three_fixed",
                  "root:0,0,120x400 x:0,0,60x20 y:0,20,90x30 z:0,50,40x50") {
        gBox("root", { gSize(&$0, 120, 400); $0.flexDirection = .column }) {
            gLeaf("x") { gSize(&$0, 60, 20) }; gLeaf("y") { gSize(&$0, 90, 30) }; gLeaf("z") { gSize(&$0, 40, 50) }
        }
    }
    try goldenArm("flex_row_gap",
                  "root:0,0,300x50 x:0,0,60x20 y:72,0,90x30 z:174,0,40x50") {
        gBox("root", { gSize(&$0, 300, 50); $0.gap = Axes(both: gPl(12)) }) {
            gLeaf("x") { gSize(&$0, 60, 20) }; gLeaf("y") { gSize(&$0, 90, 30) }; gLeaf("z") { gSize(&$0, 40, 50) }
        }
    }
}

/// `justifyContent`'s distributions and `center` place a declared main size's
/// free space. **M1b** (`distributedLegacyItems`: `betweenCount` always 1)
/// reddens `flex_row_justify_around` (it then reads evenly's 60/160/290).
@MainActor
@Test func justifyContentDistributesADeclaredMainSizesFreeSpace() throws {
    let three = [("flex_row_justify_between", JustifyContent.spaceBetween,
                  "root:0,0,400x40 a:0,0,40x40 b:160,0,70x40 c:350,0,50x40"),
                 ("flex_row_justify_around", .spaceAround,
                  "root:0,0,400x40 a:40,0,40x40 b:160,0,70x40 c:310,0,50x40"),
                 ("flex_row_justify_evenly", .spaceEvenly,
                  "root:0,0,400x40 a:60,0,40x40 b:160,0,70x40 c:290,0,50x40")]
    try #require(three.count == 3)
    for (golden, distribution, boxes) in three {
        try goldenArm(golden, boxes) {
            gBox("root", { gSize(&$0, 400, 40); $0.justifyContent = distribution }) {
                gLeaf("a") { gSize(&$0, 40, 40) }; gLeaf("b") { gSize(&$0, 70, 40) }; gLeaf("c") { gSize(&$0, 50, 40) }
            }
        }
    }
    try goldenArm("flex_row_justify_between_gap",
                  "root:0,0,400x40 a:0,0,40x40 b:160,0,70x40 c:350,0,50x40") {
        gBox("root", { gSize(&$0, 400, 40); $0.justifyContent = .spaceBetween; $0.gap = Axes(both: gPl(12)) }) {
            gLeaf("a") { gSize(&$0, 40, 40) }; gLeaf("b") { gSize(&$0, 70, 40) }; gLeaf("c") { gSize(&$0, 50, 40) }
        }
    }
    try goldenArm("flex_column_justify_center",
                  "root:0,0,60x400 a:0,120,60x40 b:0,160,60x70 c:0,230,60x50") {
        gBox("root", { gSize(&$0, 60, 400); $0.flexDirection = .column; $0.justifyContent = .center }) {
            gLeaf("a") { gSize(&$0, 60, 40) }; gLeaf("b") { gSize(&$0, 60, 70) }; gLeaf("c") { gSize(&$0, 60, 50) }
        }
    }
}

/// `alignItems` places every item on the cross axis, `alignSelf` overrides it
/// for one, and a stretched item fills the line up to its own maximum.
/// **M1c** (`alignmentFactor(_: AlignItems?)`: `.flexEnd` → 0) reddens
/// `flex_row_align_end_with_self` (a, c).
@MainActor
@Test func alignItemsAndAlignSelfPlaceEachItemOnTheCrossAxis() throws {
    try goldenArm("flex_row_align_center",
                  "root:0,0,400x100 a:0,40,40x20 b:40,20,70x60 c:110,30,50x40") {
        gBox("root", { gSize(&$0, 400, 100); $0.alignItems = .center }) {
            gLeaf("a") { gSize(&$0, 40, 20) }; gLeaf("b") { gSize(&$0, 70, 60) }; gLeaf("c") { gSize(&$0, 50, 40) }
        }
    }
    try goldenArm("flex_row_align_end_with_self",
                  "root:0,0,400x100 a:0,80,40x20 b:40,20,70x60 c:110,60,50x40") {
        gBox("root", { gSize(&$0, 400, 100); $0.alignItems = .flexEnd }) {
            gLeaf("a") { gSize(&$0, 40, 20) }
            gLeaf("b") { gSize(&$0, 70, 60); $0.alignSelf = .center }
            gLeaf("c") { gSize(&$0, 50, 40) }
        }
    }
    try goldenArm("flex_row_stretch_mixed",
                  "root:0,0,400x100 a:0,0,60x100 b:60,0,70x30 c:130,0,50x0 d:180,0,80x60") {
        gBox("root", { gSize(&$0, 400, 100) }) {
            gLeaf("a") { gSize(&$0, 60, nil) }
            gLeaf("b") { gSize(&$0, 70, 30) }
            gLeaf("c") { gSize(&$0, 50, nil); $0.alignSelf = .flexStart }
            gLeaf("d") { gSize(&$0, 80, nil); $0.maxSize = Size(width: .auto, height: gPx(60)) }
        }
    }
}

/// A reverse direction packs its items from the main end, the first item
/// outermost. **M1d** (`arrangeLegacyMainAxis`: the `nodes.reverse()` line
/// deleted) reddens both arms, and 1.6's three reverse arms.
@MainActor
@Test func aReverseDirectionPacksItemsFromTheMainEnd() throws {
    try goldenArm("flex_row_reverse",
                  "root:0,0,400x40 a:360,0,40x40 b:290,0,70x40 c:240,0,50x40") {
        gBox("root", { gSize(&$0, 400, 40); $0.flexDirection = .rowReverse }) {
            gLeaf("a") { gSize(&$0, 40, 40) }; gLeaf("b") { gSize(&$0, 70, 40) }; gLeaf("c") { gSize(&$0, 50, 40) }
        }
    }
    try goldenArm("flex_column_reverse_justify_end",
                  "root:0,0,100x400 a:0,120,100x40 b:0,50,60x70 c:0,0,80x50") {
        gBox("root", { gSize(&$0, 100, 400); $0.flexDirection = .columnReverse; $0.justifyContent = .flexEnd }) {
            gLeaf("a") { gSize(&$0, nil, 40) }; gLeaf("b") { gSize(&$0, 60, 70) }; gLeaf("c") { gSize(&$0, 80, 50) }
        }
    }
}

/// Padding plus border insets the content box edge by edge, and a nested
/// padded container does so again inside it. **M1e** (`paddedAndSized`:
/// `inset(_:_:)` returns the padding only) reddens all three arms.
@MainActor
@Test func paddingAndBorderInsetTheContentBoxEdgeByEdge() throws {
    try goldenArm("flex_row_padding_border",
                  "root:0,0,400x100 a:23,25,50x30 b:73,25,60x30 c:133,25,256x30") {
        gBox("root", { gSize(&$0, 400, 100); $0.padding = gEdges(20, 8, 4, 16); $0.border = gEdges(5, 3, 2, 7) }) {
            gLeaf("a") { gSize(&$0, 50, 30) }
            gLeaf("b") { gSize(&$0, 60, 30) }
            gLeaf("c") { gSize(&$0, nil, 30); gFlex(&$0, 1, 1, gPx(0)) }
        }
    }
    try goldenArm("flex_column_padding_asymmetric",
                  "root:0,0,120x400 a:24,16,64x40 b:24,56,64x90 c:24,146,64x60") {
        gBox("root", { gSize(&$0, 120, 400); $0.flexDirection = .column
                      $0.padding = gEdges(12, 30, 6, 18); $0.border = gEdges(4, 2, 8, 6) }) {
            gLeaf("a") { gSize(&$0, nil, 40) }; gLeaf("b") { gSize(&$0, nil, 90) }; gLeaf("c") { gSize(&$0, nil, 60) }
        }
    }
    try goldenArm("flex_nested_padding",
                  "root:0,0,400x200 mid:15,15,200x80 g1:38,38,20x10 g2:58,38,134x10 sib:215,15,40x60") {
        gBox("root", { gSize(&$0, 400, 200); $0.padding = Edges(all: gPl(10)); $0.border = Edges(all: gPl(5)) }) {
            gBox("mid", { gSize(&$0, 200, 80); $0.padding = Edges(all: gPl(20)); $0.border = Edges(all: gPl(3)) }) {
                gLeaf("g1") { gSize(&$0, 20, 10) }
                gLeaf("g2") { gSize(&$0, nil, 10); gFlex(&$0, 1, 1, gPx(0)) }
            }
            gLeaf("sib") { gSize(&$0, 40, 60) }
        }
    }
}

/// A margin offsets its item outside the item's border box, on every edge, in
/// both directions and under a reverse direction; a stretched item fills the
/// line minus its cross margins. **M1f** (`planLegacyItems`: `marginInsets`'
/// `left:`/`right:` swapped) reddens the five arms with unequal horizontal
/// margins, not the two stretch-margin arms (0 horizontal) nor
/// `flex_row_reverse_stretch` (no margin).
@MainActor
@Test func marginsOffsetEachItemOutsideItsBorderBox() throws {
    try goldenArm("flex_row_margins",
                  "root:0,0,400x100 a:20,5,40x30 b:158,2,50x40 c:336,12,60x20") {
        gBox("root", { gSize(&$0, 400, 100); $0.justifyContent = .spaceBetween }) {
            gLeaf("a") { gSize(&$0, 40, 30); $0.margin = gMargin(5, 10, 15, 20) }
            gLeaf("b") { gSize(&$0, 50, 40); $0.margin = gMargin(2, 25, 8, 3) }
            gLeaf("c") { gSize(&$0, 60, 20); $0.margin = gMargin(12, 4, 1, 18) }
        }
    }
    try goldenArm("flex_row_margin_with_grow",
                  "root:0,0,400x60 a:9,4,274x40 b:318,10,80x40") {
        gBox("root", { gSize(&$0, 400, 60) }) {
            gLeaf("a") { gSize(&$0, nil, 40); gFlex(&$0, 1, 1, gPx(0)); $0.margin = gMargin(4, 15, 6, 9) }
            gLeaf("b") { gSize(&$0, 80, 40); $0.margin = gMargin(10, 2, 3, 20) }
        }
    }
    try goldenArm("flex_row_reverse_margins",
                  "root:0,0,400x100 a:320,5,50x30 b:246,2,60x40 c:168,12,40x20") {
        gBox("root", { gSize(&$0, 400, 100); $0.flexDirection = .rowReverse }) {
            gLeaf("a") { gSize(&$0, 50, 30); $0.margin = gMargin(5, 30, 15, 10) }
            gLeaf("b") { gSize(&$0, 60, 40); $0.margin = gMargin(2, 4, 8, 20) }
            gLeaf("c") { gSize(&$0, 40, 20); $0.margin = gMargin(12, 18, 1, 6) }
        }
    }
    try goldenArm("flex_column_reverse_margins",
                  "root:0,0,100x400 a:5,320,30x50 b:2,246,40x60 c:12,168,20x40") {
        gBox("root", { gSize(&$0, 100, 400); $0.flexDirection = .columnReverse }) {
            gLeaf("a") { gSize(&$0, 30, 50); $0.margin = gMargin(10, 15, 30, 5) }
            gLeaf("b") { gSize(&$0, 40, 60); $0.margin = gMargin(20, 8, 4, 2) }
            gLeaf("c") { gSize(&$0, 20, 40); $0.margin = gMargin(6, 1, 18, 12) }
        }
    }
    try goldenArm("flex_row_stretch_with_margins",
                  "root:0,0,400x100 a:0,10,50x65 b:50,15,70x50") {
        gBox("root", { gSize(&$0, 400, 100) }) {
            gLeaf("a") { gSize(&$0, 50, nil); $0.margin = gMargin(10, 0, 25, 0) }
            gLeaf("b") { gSize(&$0, 70, nil); $0.margin = gMargin(15, 0, 5, 0)
                        $0.maxSize = Size(width: .auto, height: gPx(50)) }
        }
    }
    try goldenArm("flex_row_grow_space_between_margins",
                  "root:0,0,400x100 a:9,4,150x40 b:210,2,60x40 c:346,12,50x40") {
        gBox("root", { gSize(&$0, 400, 100); $0.justifyContent = .spaceBetween }) {
            gLeaf("a") { gSize(&$0, nil, 40); gFlex(&$0, 1, 1, gPx(0))
                        $0.maxSize = Size(width: gPx(150), height: .auto); $0.margin = gMargin(4, 15, 6, 9) }
            gLeaf("b") { gSize(&$0, 60, 40); $0.margin = gMargin(2, 25, 8, 3) }
            gLeaf("c") { gSize(&$0, 50, 40); $0.margin = gMargin(12, 4, 1, 18) }
        }
    }
    try goldenArm("flex_row_stretch_min_height_margins",
                  "root:0,0,400x100 a:0,20,50x70 b:50,10,60x75") {
        gBox("root", { gSize(&$0, 400, 100) }) {
            gLeaf("a") { gSize(&$0, 50, nil); $0.margin = gMargin(20, 0, 30, 0)
                        $0.minSize = Size(width: .auto, height: gPx(70)) }
            gLeaf("b") { gSize(&$0, 60, nil); $0.margin = gMargin(10, 0, 15, 0)
                        $0.minSize = Size(width: .auto, height: gPx(40)) }
        }
    }
    try goldenArm("flex_row_reverse_stretch",
                  "root:0,0,400x100 a:350,0,50x100 b:290,70,60x30 c:220,0,70x40") {
        gBox("root", { gSize(&$0, 400, 100); $0.flexDirection = .rowReverse }) {
            gLeaf("a") { gSize(&$0, 50, nil) }
            gLeaf("b") { gSize(&$0, 60, 30); $0.alignSelf = .flexEnd }
            gLeaf("c") { gSize(&$0, 70, nil); $0.maxSize = Size(width: .auto, height: gPx(40)) }
        }
    }
}

/// Equal growers share the line (seven into 100 rounds to 14/15 by the shared
/// rounding), and a grower's declared maximum caps it, the others taking the
/// rest. **M1g** (`planLegacyItems.axis`, the `if greedy` branch: the maximum →
/// `.infinity`) reddens both `grow_with_max` arms.
@MainActor
@Test func equalGrowersShareTheLineAndAMaximumCapsItsGrower() throws {
    try goldenArm("flex_row_seven_equal", window: (400, 200),
                  "root:0,0,100x20 c0:0,0,14x20 c1:14,0,15x20 c2:29,0,14x20 c3:43,0,14x20 c4:57,0,14x20 c5:71,0,15x20 c6:86,0,14x20") {
        gBox("root", { gSize(&$0, 100, 20) }) {
            gLeaf("c0") { gFlex(&$0, 1, 1, gPx(0)) }; gLeaf("c1") { gFlex(&$0, 1, 1, gPx(0)) }
            gLeaf("c2") { gFlex(&$0, 1, 1, gPx(0)) }; gLeaf("c3") { gFlex(&$0, 1, 1, gPx(0)) }
            gLeaf("c4") { gFlex(&$0, 1, 1, gPx(0)) }; gLeaf("c5") { gFlex(&$0, 1, 1, gPx(0)) }
            gLeaf("c6") { gFlex(&$0, 1, 1, gPx(0)) }
        }
    }
    try goldenArm("flex_row_grow_with_max",
                  "root:0,0,400x40 a:0,0,50x40 b:50,0,175x40 c:225,0,175x40") {
        gBox("root", { gSize(&$0, 400, 40) }) {
            gLeaf("a") { gFlex(&$0, 1, 1, gPx(0)); $0.maxSize = Size(width: gPx(50), height: .auto) }
            gLeaf("b") { gFlex(&$0, 1, 1, gPx(0)) }
            gLeaf("c") { gFlex(&$0, 1, 1, gPx(0)) }
        }
    }
    try goldenArm("flex_column_grow_with_max",
                  "root:0,0,100x400 a:0,0,100x50 b:0,50,100x175 c:0,225,100x175") {
        gBox("root", { gSize(&$0, 100, 400); $0.flexDirection = .column }) {
            gLeaf("a") { gFlex(&$0, 1, 1, gPx(0)); $0.maxSize = Size(width: .auto, height: gPx(50)) }
            gLeaf("b") { gFlex(&$0, 1, 1, gPx(0)) }
            gLeaf("c") { gFlex(&$0, 1, 1, gPx(0)) }
        }
    }
}

/// An auto main size sums its content through two levels of columns, and a
/// grower whose content is wider than its share is floored by that content
/// (CSS's automatic minimum, which the lowering's greedy frame keeps by leaving
/// the grown axis's minimum nil). **M1h** (`planLegacyItems.axis`, the `if
/// greedy` branch: `lo` → `resolvedDimension(animatedMin) ?? 0` for a grown
/// axis too) reddens `flex_item_floored_by_content` (50/50).
@MainActor
@Test func autoMainSizesSumTheirContentAndAGrowerIsFlooredByIt() throws {
    try goldenArm("flex_auto_height_two_levels",
                  "root:0,0,300x220 outer:0,0,240x48 inner:0,0,180x48 g1:0,0,60x24 g2:0,24,60x24 after:0,48,100x30") {
        gBox("root", { gSize(&$0, 300, 220); $0.flexDirection = .column }) {
            gBox("outer", { gSize(&$0, 240, nil); $0.flexDirection = .column
                           $0.minSize = Size(width: .auto, height: gPx(0)) }) {
                gBox("inner", { gSize(&$0, 180, nil); $0.flexDirection = .column
                               $0.minSize = Size(width: .auto, height: gPx(0)) }) {
                    gLeaf("g1") { gSize(&$0, 60, 24) }; gLeaf("g2") { gSize(&$0, 60, 24) }
                }
            }
            gLeaf("after") { gSize(&$0, 100, 30) }
        }
    }
    try goldenArm("flex_item_floored_by_content",
                  "root:0,0,100x60 squeezed:0,0,80x60 g1:0,0,80x20 other:80,0,20x60") {
        gBox("root", { gSize(&$0, 100, 60) }) {
            gBox("squeezed", { gFlex(&$0, 1, 1, gPx(0)) }) { gLeaf("g1") { gSize(&$0, 80, 20) } }
            gLeaf("other") { gFlex(&$0, 1, 1, gPx(0)) }
        }
    }
}
