import Testing
@testable import MetalUI

// MARK: - Plan task 7: the roll call every stage's exit criterion is read off
//
// Introduced by stage 3's lane 3 at the end of `ScrollViewTests.swift`
// (spec 3.4, `LR-BI`/`LR-BN`); **moved into a file of its own by stage 4's lane
// 4** (`LR-CF`), because that lane's subjects include `TombstoneTests.swift`,
// which sorts AFTER `ScrollViewTests.swift`. The test's third `#require` reads
// what has been recorded by the time it runs, so it has to run last; the `ZZ…`
// prefix is `ZZDemoPixels.swift`'s, chosen so no later file sorts after this one
// by accident. Nothing else moved: the registry is still
// `AuthorityCoverage.swift` and the literals are still hand-derived here.

/// **The roll call.** Every parameterised scenario in `AXNodeTests`,
/// `AbsoluteOverlayTests`, `AccessibilityDefaultsTests`, `AccessibilityTreeTests`,
/// `DecorationPaintTests`, `DeferredTests`, `EnvironmentTests`, `FocusTests`,
/// `ListTests`, `MeasurePerformanceTests`, `PresentationWindowTests`,
/// `ScrollIndicatorTests`, `ScrollRoutingTests`, `ScrollViewTests` and
/// `TombstoneTests` ran under **both** layout authorities — 82 since stage 5's
/// lane 3. Its lane 2 added seven: `DeferredTests`' four element-level scenarios and
/// its demo-shaped scrim, `AbsoluteOverlayTests`' divergence-11 pin, and
/// `ListTests`' `aListInsideADeferredIgnoresTheEscapedScrollersOffset` (`LR-CN`,
/// `LR-CO`) — plan task 7 stage 5's exit criterion. Its lane 3 added eight, the
/// must-not-move set: `PresentationWindowTests`' six and the two in-flow pins it
/// parameterised, one each in `DecorationPaintTests` and `EnvironmentTests`.
///
/// **Why a test at all.** A `@Test(arguments:)` test counts as ONE test in the
/// summary line — measured on this suite, `LR-BI` — so parameterising 82
/// scenarios over two authorities moves the total by nothing and the exit
/// criterion cannot be read off it. Reducing the `arguments:` list to `[.legacy]`
/// (stage 3's mutation **M3c**, stage 4's **M3a** and **M4d**) would pass every
/// test, move no count, and deliver none of the stage.
///
/// **Two halves, and only one of them is here** (`LR-BN`; see
/// `AuthorityCoverage`'s doc for why the design's "counter" shape could not
/// be made falsifiable). `AuthorityCoverage.record` verifies the whole set
/// the moment the last expected name arrives, wherever that arm lands in the run.
/// This test holds the hand-derived literals: the 82 names, and the `arguments:`
/// list itself.
///
/// **Declared in the last file of the suite**, because its third `#require`
/// reads what has been recorded so far. Swift Testing runs a file's tests in
/// source order and the files in path order — `AXNodeTests` →
/// `AbsoluteOverlayTests` → `AccessibilityDefaultsTests` →
/// `AccessibilityTreeTests` → `DecorationPaintTests` → `DeferredTests` →
/// `EnvironmentTests` → `FocusTests` → `ListTests` → `MeasurePerformanceTests` →
/// `PresentationWindowTests` → `ScrollIndicatorTests` →
/// `ScrollRoutingTests` → `ScrollViewTests` → `TombstoneTests` → here —
/// measured twice at stage 4 lane 5's HEAD as it was measured twice at stage 3's
/// and at lanes 3's and 4's, and re-read in stage 5 lane 2's unfiltered runs, so
/// by here all 82 have run. If that ever changes this fails **naming the scenarios it had not
/// yet seen**, rather than passing quietly.
@Test @MainActor func everyParameterisedScenarioRanUnderBothLayoutAuthorities() throws {
    try #require(LayoutAuthority.allCases.count == 2,
                 "the exit criterion is 'both authorities'; a third would need every literal in the nine suites re-derived")
    try #require(AuthorityCoverage.authorities == LayoutAuthority.allCases,
                 "every scenario is declared over this one list — M3c/M4d reduce it and nothing else would say so")
    try #require(AuthorityCoverage.expected.count == 82,
                 """
                 the hand-derived scenario count: 16 routing + 14 indicator + 4 ScrollViewTests \
                 + 21 ListTests + 3 AXNodeTests + 5 AccessibilityDefaultsTests \
                 + 1 AccessibilityTreeTests + 1 FocusTests + 1 TombstoneTests \
                 + 2 MeasurePerformanceTests + 5 DeferredTests + 1 AbsoluteOverlayTests \
                 + 6 PresentationWindowTests + 1 DecorationPaintTests + 1 EnvironmentTests
                 """)

    let missing = AuthorityCoverage.expected.subtracting(AuthorityCoverage.seen.keys).sorted()
    try #require(missing.isEmpty,
                 "these scenarios recorded no coverage: \(missing)")
    let all = Set(LayoutAuthority.allCases)
    for (name, authorities) in AuthorityCoverage.seen.sorted(by: { $0.key < $1.key }) {
        #expect(authorities == all, "\(name) ran under \(authorities.count) authority, not both")
    }
    #expect(AuthorityCoverage.verifiedWholeSet,
            "record() must have verified the whole set once the last scenario arrived")
}
