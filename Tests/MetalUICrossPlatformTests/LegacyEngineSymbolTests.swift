// The mechanical closing check of plan task 7 (spec
// `docs/superpowers/specs/2026-09-24-engine-stage-10-design.md` §6 lane 2,
// test N2.1; rulings LR-P item 0, LR-FP, LR-FR F1–F2).
//
// **Compiled out on Windows** (LR-FP item 4, PC-B's rule for a test that
// needs a platform API): Windows has no `dlsym`, and `GetProcAddress` sees only
// what an executable exports. macOS and Linux (`swift:6.4-noble`) both export
// the test process's Swift symbols to `dlsym(RTLD_DEFAULT, …)` — measured,
// `docs/probes/stage-10-legacy-symbols.txt` block E.
#if canImport(Darwin) || canImport(Glibc)
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Testing
import MetalUI

/// `RTLD_DEFAULT`: `(void *)-2` on Darwin, `NULL` on Glibc.
private var defaultHandle: UnsafeMutableRawPointer? {
    #if canImport(Darwin)
    UnsafeMutableRawPointer(bitPattern: -2)
    #else
    nil
    #endif
}

/// Whether `name` (a mangled Swift symbol, without the leading `_` Darwin's
/// `nm` prints) resolves in this process.
private func resolves(_ name: String) -> Bool {
    dlsym(defaultHandle, name) != nil
}

/// Every name below is copied from `docs/probes/stage-10-legacy-symbols.txt`,
/// whose blocks carry the command that printed each one.
///
/// Block A — deleted by stage 9, printed at `b9a5d7f` (the commit before the
/// deletion) by `nm -gU` over `MetalUI`'s and `MetalUILayout`'s objects.
private let deletedByStageNine: [String] = [
    "$s13MetalUILayout13computeLayout_4root9available0E8FontSizeyAA0D4TreeC_AA0D6NodeIDVAA014AvailableSpaceH0VSdtF",
    "$s7MetalUI10LayoutPassV11requestNode5style8children0A8UILayout0cF2IDVAG5StyleV_SayAIGtF",
    "$s7MetalUI10LayoutPassV11requestLeaf5style7measure0A8UILayout0C6NodeIDVAG5StyleV_AG5SizeDVAG08OptionalM1DV_AG014AvailableSpaceM0VtYbctF",
    "$s7MetalUI5FrameC11requestNode5style8children0A8UILayout06LayoutE2IDVAG5StyleV_SayAIGtF",
    "$s7MetalUI5FrameC11requestLeaf5style7measure0A8UILayout12LayoutNodeIDVAG5StyleV_AG5SizeDVAG08OptionalM1DV_AG014AvailableSpaceM0VtYbctF",
    "$s7MetalUI15LayoutAuthorityOMa",
    "$s7MetalUI5FrameC23legacyRootLayoutCounterAC06LegacyefG0CSgvgZ",
]

/// Block B — deleted, or moved out of the kernel, by stage 10, printed at
/// `8095fd9` by `nm -gU` over the suite's own test binary.
/// `MetalUILayout.Style.flexGrow`'s getter is here because `Style` moved to
/// `MetalUI` (LR-FM item 3); its twin is a positive control.
private let deletedByStageTen: [String] = [
    "$s13MetalUILayout5StyleV8flexGrowSfvg",
    "$s13MetalUILayout5StyleV8flexWrapAA04FlexE0Ovg",
    "$s13MetalUILayout5StyleV12alignContentAA05AlignE0OSgvg",
    "$s13MetalUILayout5StyleV11aspectRatioSfSgvg",
    "$s13MetalUILayout5StyleV8overflow0A6UICore4AxesVyAA8OverflowOGvg",
    "$s13MetalUILayout5StyleV6border0A6UICore5EdgesVyAE6LengthOGvg",
    "$s13MetalUILayout8FlexWrapOMa",
    "$s13MetalUILayout12AlignContentOMa",
    "$s13MetalUILayout8OverflowOMa",
    "$s7MetalUI13StyledElementPAAE8flexWrapyx0A8UILayout04FlexF0OF",
    "$s7MetalUI13StyledElementPAAE12alignContentyx0A8UILayout05AlignF0OF",
]

/// Block C — the `MetalUI`-module twins a regression re-adding a deleted
/// field, enum, modifier or style-taking registrar to the MOVED `Style` would
/// export (LR-FR F1): the module is part of the mangled name, so block A's and
/// B's spellings cannot see such a re-add.
private let twinsAfterTheMove: [String] = [
    "$s7MetalUI5StyleV6border0A6UICore5EdgesVyAE6LengthOGvg",
    "$s7MetalUI5StyleV8flexWrapAA04FlexE0Ovg",
    "$s7MetalUI5StyleV12alignContentAA05AlignE0OSgvg",
    "$s7MetalUI5StyleV11aspectRatioSfSgvg",
    "$s7MetalUI5StyleV8overflow0A6UICore4AxesVyAA8OverflowOGvg",
    "$s7MetalUI13StyledElementPAAE8flexWrapyxAA04FlexF0OF",
    "$s7MetalUI13StyledElementPAAE12alignContentyxAA05AlignF0OF",
    "$s7MetalUI8FlexWrapOMa",
    "$s7MetalUI12AlignContentOMa",
    "$s7MetalUI8OverflowOMa",
    "$s7MetalUI10LayoutPassV11requestNode5style8children0A8UILayout0cF2IDVAA5StyleV_SayAIGtF",
    "$s7MetalUI5FrameC11requestNode5style8children0A8UILayout06LayoutE2IDVAA5StyleV_SayAIGtF",
]

/// Block D — positive controls. If one fails to resolve the instrument is
/// broken (a stripped binary, a wrong handle), and the test says so rather
/// than reading every absent name as absent.
private let positiveControls: [String] = [
    "$s7MetalUI5StyleV8flexGrowSfvg",
    "$s7MetalUI13StyledElementPAAE8flexGrowyxSfF",
    "$s13MetalUILayout10LayoutTreeC013computeNativeC04root8proposal2inAA0C11MeasurementVAA0C6NodeIDV_AA12ProposedSizeVAA0C4RectVtF",
    "$s7MetalUI10LayoutPassV17requestNativeLeaf7measureAA14ProposalNodeIDV0A8UILayout0C11MeasurementVAH12ProposedSizeVYbc_tF",
    "$s7MetalUI5FrameC17requestNativeLeaf7measure0A8UILayout12LayoutNodeIDVAF0I11MeasurementVAF12ProposedSizeVYbc_tF",
]

/// **N2.1.** No symbol of the CSS engine stage 9 deleted, and none of the
/// `Style` vocabulary stage 10 deleted or moved out of the layout kernel, is
/// present in the test process — which links every module the app does.
///
/// **It cannot skip** (LR-FP item 2): no `.enabled(if:)`, no early return; the
/// positive controls and the absent list's count are `try #require`d first.
/// **What it cannot see** (LR-FP item 3): an entry point re-added under a new
/// name or signature — the plain-import guards and the recorded grep cover
/// that. Block A's `computeLayout` and both `requestLeaf` names spell the
/// deleted `AvailableSpace`, so no source can re-export them: those rows record
/// the deletion rather than trip on a regression.
///
/// Mutations (record §53 §5): M2a (`flexWrap` re-added to the moved `Style`),
/// M2c (`Style` moved back to `MetalUILayout`), M2d (the resolver always
/// false), M2f (`LayoutPass.requestNode(style:children:)` re-added), M2g
/// (`LayoutAuthority` re-added).
@Test func theLegacyEngineSymbolsAreAbsentFromTheTestProcess() throws {
    for name in positiveControls {
        try #require(resolves(name), "positive control \(name) does not resolve: the instrument is broken")
    }
    let absent = deletedByStageNine + deletedByStageTen + twinsAfterTheMove
    try #require(deletedByStageNine.count == 7 && deletedByStageTen.count == 11 && twinsAfterTheMove.count == 12)
    try #require(absent.count == 30)
    try #require(Set(absent).count == absent.count, "a name is listed twice")
    for name in absent {
        #expect(!resolves(name), "\(name) resolves in the test process")
    }
}
#endif
