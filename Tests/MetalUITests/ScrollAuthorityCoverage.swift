import Testing
@testable import MetalUI

// Plan task 7, stage 3, lane 3 (`LR-BI`, corrected by `LR-BN`): the roll call the
// stage's exit criterion is read off.
//
// `ScrollRoutingTests`, `ScrollIndicatorTests` and `ScrollViewTests` run their
// scenarios under **both** layout authorities, as `@Test(arguments:)` cases. A
// parameterised test counts as ONE test in the summary line, so the suite total
// cannot say whether the second authority ran — hence this registry and
// `everyScrollScenarioRanUnderBothLayoutAuthorities` (spec 3.4), which reads it.

/// Every parameterised scroll scenario's name, and which authorities it has been
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
/// - `everyScrollScenarioRanUnderBothLayoutAuthorities` holds the hand-derived
///   literals — the 34 names and the `arguments:` list itself — and reads what has
///   been recorded by the time it runs.
///
/// **The second half does depend on order, and the dependency is measured rather
/// than assumed**: Swift Testing runs a file's tests in source order and the files
/// in path order, so `ScrollIndicatorTests` → `ScrollRoutingTests` →
/// `ScrollViewTests`, and 3.4 is declared at the END of the last of the three.
/// Measured twice at this HEAD, identical both times. If that ever changes the
/// test fails **naming the scenarios it had not yet seen**, rather than passing
/// quietly — which is why the completeness check above does not live here.
@MainActor
enum ScrollAuthorityCoverage {
    /// The single `arguments:` list every parameterised scroll scenario is
    /// declared over. **Mutation M3c edits this**, and 3.4 reads it: a lane that
    /// quietly reduced it to `[.legacy]` would otherwise pass every test and move
    /// no count.
    /// **`nonisolated`**: `@Test(arguments:)` evaluates its list outside any
    /// actor, so a main-actor-isolated one does not compile.
    nonisolated static let authorities: [LayoutAuthority] = LayoutAuthority.allCases

    /// The 34 scenario names, written out by hand before the first run (practices
    /// shape 13: a count a later loop indexes on is a literal, not a derivation).
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
        // ScrollRoutingTests (16)
        "aWheelEventInsideARegionScrollsIt",
        "aWheelEventOutsideEveryRegionScrollsNothing",
        "theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove",
        "momentumDeltasScrollLikeDirectOnes",
        "aNestedRegionClippedOutOfViewByItsParentDoesNotReceiveWheelEvents",
        "aHorizontalScrollViewMovesOnDeltaXNotDeltaY",
        "scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind",
        "aDeferredScrollViewTakesTheWheelFromAnOverlappingSiblingBeneathIt",
        "withinOneLayerTheLastRegisteredRegionStillWins",
        "scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout",
        "rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange",
        "nestedScrollViewsInnermostWinsAndPoppingRestoresTheOuterContext",
        "aSiblingAfterAScrollViewSeesNoScrollContext",
        "anOpaqueDeferredScrimSwallowsAWheelEventInsteadOfScrollingTheListBeneath",
        "aNonOpaqueDeferredScrimLetsTheWheelReachTheListBeneath",
        "aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints",
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
    ]

    private(set) static var seen: [String: Set<LayoutAuthority>] = [:]
    /// Set by `record` when the last expected name arrives and every OTHER
    /// scenario has been verified — so a reader can tell "the order-independent
    /// half ran" from "it never ran because the run was filtered".
    private(set) static var verifiedWholeSet = false

    /// Called first thing by every parameterised scroll scenario, with `#function`
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
    /// is covered by `everyScrollScenarioRanUnderBothLayoutAuthorities`, which
    /// runs after all of them.
    static func record(_ function: String, _ authority: LayoutAuthority,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let name = String(function.prefix { $0 != "(" })
        #expect(expected.contains(name),
                "\(name) records coverage but is not in ScrollAuthorityCoverage.expected — add it there (and re-derive the 34)",
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
