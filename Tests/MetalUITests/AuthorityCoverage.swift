import Testing
@testable import MetalUI

// Plan task 7, stage 3, lane 3 (`LR-BI`, corrected by `LR-BN`): the roll call the
// stage's exit criterion is read off. **Renamed from `ScrollAuthorityCoverage` by
// stage 4's lane 3** (`LR-CB`), in the same commit that added `ListTests`'
// twenty scenarios to it: a name that says "scroll" over a set containing a
// `List`'s windowing scenarios is a name that lies to the next reader, and the
// same goes for `everyScrollScenarioRanUnderBothLayoutAuthorities`, now
// `everyParameterisedScenarioRanUnderBothLayoutAuthorities`.
//
// `ScrollRoutingTests`, `ScrollIndicatorTests`, `ScrollViewTests`, `ListTests`,
// — since stage 4's lane 4 — `AXNodeTests`, `AccessibilityDefaultsTests`,
// `AccessibilityTreeTests`, `FocusTests` and `TombstoneTests`, — since its
// lane 5 — `MeasurePerformanceTests`, — since stage 5's lane 2 —
// `DeferredTests` and `AbsoluteOverlayTests`, and — since its lane 3 —
// `PresentationWindowTests`, `DecorationPaintTests` and `EnvironmentTests`
// run their scenarios under **both** layout authorities, as `@Test(arguments:)`
// cases. A parameterised test counts as ONE test in the summary line, so the
// suite total cannot say whether the second authority ran — hence this registry
// and `everyParameterisedScenarioRanUnderBothLayoutAuthorities` (spec 3.4),
// which reads it.

/// Every parameterised scenario's name, and which authorities it has been
/// seen under this run.
///
/// **Not a counter of executions** (this is `LR-BN`'s correction to `LR-BI`).
/// The design asked for "a counter incremented by the parameterised arms"; Swift
/// Testing does not specify the order tests run in, so a counter read by a test
/// that happens to run first reads zero and passes — practices shape 14's "a test
/// that cannot fail", bought at the price of the stage's exit criterion. The
/// registry answers the same question in two halves, one of which is
/// order-independent:
///
/// - **`record` itself verifies the whole set** the moment the last expected name
///   arrives, so in an unfiltered run the completeness check fires exactly once,
///   inside whichever arm completes the set, whatever the order.
/// - `everyParameterisedScenarioRanUnderBothLayoutAuthorities` holds the hand-derived
///   literals — the 54 names and the `arguments:` list itself — and reads what has
///   been recorded by the time it runs.
///
/// **The second half does depend on order, and the dependency is measured rather
/// than assumed**: Swift Testing runs a file's tests in source order and the files
/// in path order. Stage 3 read that off three `Scroll*` files and stage 4's lane 3
/// added `ListTests.swift`, which sorts before all three, so the roll call could
/// stay at the end of `ScrollViewTests.swift` (`LR-CB`).
///
/// **Stage 4's lane 4 broke that arrangement and moved the roll call rather than
/// working around it** (`LR-CF`). Its subjects include
/// `Tests/MetalUITests/TombstoneTests.swift`, which sorts AFTER
/// `Tests/MetalUITests/ScrollViewTests.swift` — exactly the case the previous
/// version of this paragraph warned a later file would hit. So
/// `everyParameterisedScenarioRanUnderBothLayoutAuthorities` now lives in its own
/// `Tests/MetalUITests/ZZAuthorityRollCall.swift`, whose `ZZ…` prefix is
/// `ZZDemoPixels.swift`'s, chosen so that no future test file can sort after it
/// without being named for the purpose. The contributing files sort
/// `AXNodeTests` → `AbsoluteOverlayTests` → `AccessibilityDefaultsTests` →
/// `AccessibilityTreeTests` → `DecorationPaintTests` → `DeferredTests` →
/// `EnvironmentTests` → `FocusTests` → `ListTests` →
/// `MeasurePerformanceTests` → `PresentationWindowTests` → `ScrollIndicatorTests` →
/// `ScrollRoutingTests` → `ScrollViewTests` → `TombstoneTests`, all before
/// `ZZAuthorityRollCall` (twelve since stage 5's lane 2 added the two exit suites,
/// fifteen since its lane 3 added `PresentationWindowTests` and parameterised one
/// pin each in `DecorationPaintTests` and `EnvironmentTests`).
/// Measured twice at stage 4 lane 5's HEAD as it was at lane 4's, identical
/// both times.
///
/// `ListLoweringTests.swift` arrived in stage 4's lane 1 and is **not** in the
/// argument, because it contributes no name: its nine tests each run both
/// authorities inside one body through `LayoutDifferential.compare`, so none of
/// them is a `@Test(arguments:)` case and none calls `record`.
///
/// If the ordering ever changes the test fails **naming the scenarios it had not
/// yet seen**, rather than passing quietly — which is why the completeness check
/// above does not live here.
@MainActor
enum AuthorityCoverage {
    /// The single `arguments:` list every parameterised scenario is
    /// declared over. **Mutations M3c (stage 3) and M3a (stage 4) edit this**, and
    /// 3.4 reads it: a lane that quietly reduced it to `[.legacy]` would otherwise
    /// pass every test and move no count.
    /// **`nonisolated`**: `@Test(arguments:)` evaluates its list outside any
    /// actor, so a main-actor-isolated one does not compile.
    nonisolated static let authorities: [LayoutAuthority] = LayoutAuthority.allCases

    /// The 38 scenario names, written out by hand before the first run (practices
    /// shape 13: a count a later loop indexes on is a literal, not a derivation).
    ///
    /// **87 − 49 since stage 9's lane 1** (record §51, `LR-FH` item 1): the five
    /// files that also use the differential harness — `ScrollRoutingTests` (16),
    /// `ListTests` (21), `DeferredTests` (5), `PresentationWindowTests` (6) and
    /// `DecorationPaintTests` (1) — collapsed their scenarios to the one
    /// authority, and their names left this set. Lane 2 collapses the other 38
    /// and deletes this registry with the roll call.
    ///
    /// **82 + 5 since stage 6b's lane 1** (`LR-DH`): the five AV tests —
    /// `AccessibilityDefaultsTests`' `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`
    /// (kept out below by stage 4 because `display: none` had no proposal lowering)
    /// and `AccessibilityTreeTests`' four `hidden()` tests — now that `hidden()`
    /// lowers as if shown and joins `Frame.hiddenNodes`.
    ///
    /// **74 + 8 since stage 5's lane 3** (`LR-CO`): `PresentationWindowTests`' six
    /// scenarios (spec 3.1–3.6, the must-not-move set through real windows) and the
    /// two existing in-flow pins spec 3.7–3.8 parameterise,
    /// `DecorationPaintTests`' `aDeferredPortalInsideAFadedSubtreeIsStillFaded` and
    /// `EnvironmentTests`' `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`.
    ///
    /// **67 + 7 since stage 5's lane 2** (`LR-CN`, `LR-CO`): `DeferredTests`' four
    /// element-level scenarios, hosted, plus its new demo-shaped scrim (2.5);
    /// `AbsoluteOverlayTests`' one (divergence 11, whose proposal arm asserts the
    /// report); and `ListTests`' `aListInsideADeferredIgnoresTheEscapedScrollersOffset`,
    /// kept out below on a claim record §29 §2.3 refutes. `DeferredTests`' five
    /// pass-level tests are **not** here and each says why at its declaration (no
    /// element, no layout, no authority in its call path — `LR-BN`), nor is
    /// `anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame`, an exit test
    /// with no authority argument to take.
    ///
    /// **65 + 2 since stage 4's lane 5**, which parameterised the two ungated
    /// `List` performance scenarios spec §4.1 rows 5 and 6 protect. The third,
    /// `aListsWorkIsTheSameFor100kRowsAsFor500`, is parameterised too and is
    /// deliberately **not** here: it is env-gated
    /// (`METALUI_RUN_100K_LIST_TEST`), so its name would be permanently missing
    /// from `seen` and would redden the roll call on every healthy run. Its own
    /// declaration says so, and `aListsWorkIsTheSameFor160RowsAsFor40` is the
    /// ungated twin that carries the name.
    ///
    /// **54 + 11 since stage 4's lane 4**, which parameterised the suites holding
    /// what spec §4.1 rows 2, 3 and 4 protect: the two excursion pins,
    /// `AXNodeTests`' three `List` tests, five of
    /// `AccessibilityDefaultsTests`' six and `AccessibilityTreeTests`' one
    /// table assertion. The sixth accessibility test,
    /// `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`, is
    /// **not** here and its own declaration says why: its subject is `hidden()`,
    /// and `display: none` has no proposal lowering, so a `.proposal` frame over
    /// it aborts rather than failing (`LR-CF`).
    ///
    /// **34 + 20 at stage 4's lane 3.** `ListTests` has 22 `@Test`s; two are
    /// not here and each says so at its own declaration:
    /// `aListInsideADeferredIgnoresTheEscapedScrollersOffset`, because `Deferred`
    /// as a presentation root is stage 5's (**stage 5's lane 2 added it**, above:
    /// the reason did not hold — the scenario's `Deferred` is in-flow), and
    /// `aLegacySpelledListRowAbortsAProductionProposalFrame`, which is a
    /// child-process probe about the spelling the lane replaced and has no
    /// authority argument to take.
    ///
    /// **34, not the 37 the design predicted.** `ScrollViewTests`' three
    /// `ScrollChrome.clamp` tests — `theOffsetClampsToTheScrollableRange`,
    /// `contentShorterThanTheViewportDoesNotScroll` and
    /// `aStoredOffsetPastTheEndIsClampedWhenItIsRead` — call one static function
    /// with three `Double`s. No element, no `Frame`, no authority anywhere in
    /// their call path, so an authority argument would be an argument the body
    /// never reads: the two cases would run the identical assertions and one of
    /// them could never fail differently from the other (`LR-BN`).
    static let expected: Set<String> = [
        // ScrollIndicatorTests (14)
        "theIndicatorIsTheLastPrimitiveInTheScene",
        "contentThatFitsDrawsNoIndicator",
        "theThumbIsProportionalAndFlooredAtTwentyPoints",
        "theThumbReachesTheEndOfItsTrackAtMaximumOffset",
        "theIndicatorRequestsFramesWhileFadingAndStopsWhenDone",
        "aScrollFollowingAnIdleThatPausedTheDisplayLinkStillShowsTheIndicator",
        "theIndicatorStillFadesAndTheWindowReturnsIdleAfterWakingFromAPausedLink",
        "aNeverScrolledScrollViewPaintsNoIndicatorOnTheWindowsPreTickFirstFrame",
        "theIndicatorFadesOnARampAndTakesItsColourFromTheScrollIndicatorToken",
        "theHorizontalIndicatorLiesAlongTheBottomOfItsViewport",
        "theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt",
        "hiddenEmitsNoIndicatorRect",
        "automaticStillPaintsTheIndicatorInTheSameFixture",
        "hiddenIndicatorDoesNotKeepTheWindowDirtyOrTheLinkAwake",
        // ScrollViewTests (4)
        "theContentNodeOverflowsTheViewport",
        "aScrollViewOfTextDoesNotShrinkItsContentToTheViewport",
        "aScrollViewsCornerRadiusReachesEveryPrimitiveItClips",
        "aScrollViewWithNoCornerRadiusClipsSquare",
        // AXNodeTests (3) — stage 4, lane 4 (`LR-BU`)
        "aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount",
        "aVirtualizedListsLogicalCountIsTheFullDataCountEvenWhenEveryRowFits",
        "aCallerDeclaredAXNodeOnAListSurvivesLogicalCountBeingAdded",
        // AccessibilityDefaultsTests (5) — stage 4, lane 4 (`LR-BU`, `LR-CF`)
        "combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows",
        "aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices",
        "activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded",
        "scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame",
        "aClientDoesNotChangeStateRetention",
        // AccessibilityTreeTests (1) — completeness only, stage 4, lane 4
        "aLabelledListIsStillATable",
        // FocusTests (1) — stage 4, lane 4 (`LR-BU`)
        "aFocusedListRowSurvivesABoundedExcursionButNotALongerOne",
        // TombstoneTests (1) — stage 4, lane 4 (`LR-BU`)
        "aListRowsStateSurvivesABoundedExcursionButNotALongerOne",
        // MeasurePerformanceTests (2) — stage 4, lane 5 (`LR-CG`)
        "aListsWorkIsTheSameFor160RowsAsFor40",
        "theResidentEntrySetStaysBoundedWhileScrolling10kRows",
        // AbsoluteOverlayTests (1) — stage 5, lane 2 (divergence 11, `LR-CN`)
        "anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt",
        // EnvironmentTests (1) — stage 5, lane 3: an existing in-flow pin,
        // parameterised
        "aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope",
        // AccessibilityDefaultsTests (1), AccessibilityTreeTests (4) — stage 6b,
        // lane 1 (`LR-DH`): the five AV tests, `hidden()` now lowered
        "aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame",
        "hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce",
        "aHiddenRootPublishesNothing",
        "aHiddenInnerModifierLayerSuppressesEverythingInsideIt",
        "aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient",
    ]

    private(set) static var seen: [String: Set<LayoutAuthority>] = [:]
    /// Set by `record` when the last expected name arrives and every OTHER
    /// scenario has been verified — so a reader can tell "the order-independent
    /// half ran" from "it never ran because the run was filtered".
    private(set) static var verifiedWholeSet = false

    /// Called first thing by every parameterised scenario, with `#function`
    /// and the authority its arm is running under.
    ///
    /// Raises its own issues, so a scenario whose name is not in `expected` — a
    /// rename, or one added without being listed — reddens **in its own arm**,
    /// wherever in the run that arm lands.
    ///
    /// **The whole-set check skips the name it is called with, and that is not a
    /// hole.** Swift Testing runs one test's argument cases back to back
    /// (measured: `… → .legacy` then `… → .proposal` for the same function), so
    /// when the last expected name first arrives every OTHER name has had all its
    /// arms — but that name itself has had exactly one, and including it would
    /// make this fire on every healthy run. The one scenario it cannot speak for
    /// is covered by `everyParameterisedScenarioRanUnderBothLayoutAuthorities`, which
    /// runs after all of them.
    static func record(_ function: String, _ authority: LayoutAuthority,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let name = String(function.prefix { $0 != "(" })
        #expect(expected.contains(name),
                "\(name) records coverage but is not in AuthorityCoverage.expected — add it there (and re-derive the 38)",
                sourceLocation: sourceLocation)
        seen[name, default: []].insert(authority)
        guard !verifiedWholeSet, Set(seen.keys) == expected else { return }
        verifiedWholeSet = true
        let all = Set(LayoutAuthority.allCases)
        for (other, authorities) in seen where other != name && authorities != all {
            Issue.record("\(other) ran under \(authorities.count) authority, not both — the exit criterion is both",
                         sourceLocation: sourceLocation)
        }
    }
}
