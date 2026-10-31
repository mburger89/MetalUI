# Dashboard report: Text padding parity and periodic timelines under the harness - decisions

Rulings for two items an app (a dashboard) reported. Prefix `DX-`. Branch `fix/mfd-text` from master `b881c237`.
**Nothing is published.** **Next unused: `DX-D`.** Divergence label 208 (207 may be taken by a sibling track).

## DX-A - `advance(by:)` alone re-evaluates a periodic `TimelineView` under `TestWindow`

**Report.** Under `TestWindow`, `TimelineView(.periodic(...))` only picked up `advance(by:)` after `setNeedsRedraw()` plus `tick()`.
**Cause (harness only; the live framework is right).** Two things, both in how the harness ran the store's clock, neither in `TimelineView`:
1. `TimelineStore.clockOffset` is `nil` until the first NONZERO display-link timestamp, when it is taken as `Date.now - timestamp` (`KF-Y`). So the first `advance(by:)` *anchored* the clock instead of moving it: the date the timeline saw did not advance by the seconds advanced.
2. The wake for the next entry is a `Task` that sleeps on the wall clock (`TimelineStore.taskScheduler`). A harness never lets it elapse, so nothing dirtied the window, and `tick()` draws only a dirty window. Hence the `setNeedsRedraw()`.
Live: the first frame (timestamp 0) reads the wall clock and schedules the wake by `Task`; the wake fires the state write path; the next frame anchors the offset on the link. A periodic timeline fires with nothing else redrawing. Reproduced and checked by reading, not changed.
**Ruling.** `TestApp` puts the window's timeline store on a simulated clock before the first build (`Window.testingSimulateTimelineClock(anchor:)`, `package`; `TimelineStore.useSimulatedClock`): `clockOffset` is the window's creation date, so a date is that date plus `now`, and the scheduler *holds* the one wake instead of sleeping. `TestWindow.tick()` first fires the held wake if its date is not after `now`'s (`Window.testingFireDueTimelineWake`), from outside every phase, through the same `StateTable.onWrite` path a live wake takes, then draws. `advance(by:)` therefore needs nothing else; `advanceFrames` and every action that ticks do the same. `testingTimelineClockOffset = 0` still works (it overrides the anchor and forgets the cursors, `RK-AD`/`RK-AE`). A timeline written `.periodic(from: .now, by: 1)` shows its next entry one second of `now` after the window opened.
No public API (the hooks are `package`; `advance(by:)`'s doc comment and `docs/testing.md` say it). No sleeps (`now` is the only clock).
**Class.** M (harness). **Pins.** `advanceAloneReevaluatesAPeriodicTimeline`, `oneAdvanceAcrossSeveralEntriesShowsTheLatestAndKeepsGoing`, `aTimelineThatLeftTheTreeWakesNothing` (`HarnessTimelineTests`); the existing `TimelineViewTests` and `pinningTheTimelineClockAfterTheFirstFrameDropsTheWallClockDate` stay green.
**Cost if wrong.** A test that counted on the wall-clock anchor (none did) sees dates relative to creation instead.

## DX-B - SwiftUI's padding spellings on both vocabularies (additive)

**What was true before** (probed with `typecheckFile`, plain import; `TextModifierParityCompileGuards`):
- `Text("x").padding(8).background(Color(.surface))` and the reverse order **compiled** (`StyledElement.padding(_: Pixels)` returning `ModifiedElement`, `background(_: Color)` returning `Self`). The reported "Text can't take padding/background" was not true for these.
- `Text.padding` took `Pixels` or `Edges<Length>` only; `Text("x").padding(Edges(all: 8))` failed (`Edges<Int>` to `Pixels`) because the only edge form took `Edges<Length>` and `Length` has no literal. A stack and `ProposalText` took **only** `Edges<Pixels>`: `HStack{…}.padding(8)` and `ProposalText("x").padding(8)` did not compile. That is the `Edges<Length>`/`Edges<Pixels>` split reported.
- `padding(.horizontal, 8)`, `padding(EdgeInsets(...))` and `padding()` compiled nowhere (`Edge.Set` and `EdgeInsets` did not exist).
**Ruling.** Add, never change: `Edge.Set` (an `OptionSet`, nested in the existing `Edge`) and `EdgeInsets` (`Pixels`, leading = left); on `StyledElement` (so `Text`, boxes) `padding(_: Edge.Set, _: Pixels)`, `padding(_: EdgeInsets)` and `padding(_: Edges<Pixels>)`; on `ProposalElementGroup` (stacks, `ProposalText`, modified content) `padding(_: Pixels)`, `padding(_: Edge.Set, _: Pixels)` and `padding(_: EdgeInsets)`. Each lowers to the one existing modifier of its vocabulary, so layout is the existing layout. `Edges<Length>` stays for rem lengths (`FR-Q`). **Ambiguity found and settled:** a `Component` over proposal content is both a `Component` and a `ProposalElementGroup`, so the new `padding(_: Pixels)` made `C().padding(4)` ambiguous (`LayoutAuthorityTests`' Component-wrap arm broke the build); `extension Component where Self: ProposalElementGroup` re-declares `padding(_: Pixels)` as `Component`'s own (more specialised, same behaviour, `OM-D`).
**Left out, by name (divergence 208).** `padding()`, `padding(.horizontal)` and a `nil` length (SwiftUI's platform default amount: unmeasured here, so not guessed), and the edge forms on a `Component` (it wraps members; additive later). `leading`/`trailing` are left/right (no RTL, divergence 25).
**Class.** D (208). **Pins.** `textTakesTheSwiftUIPaddingSpellings`, `aStackAndProposalTextTakeTheSameSpellingsWithTheSameGrowth`, `leadingPaddingPushesTheContentRightOnAStack`, `edgeInsetsPutEachInsetOnItsOwnEdge`, `aProposalComponentsPaddingStaysTheComponents`, `aBackgroundAfterTextPaddingFillsThePaddedFrame` (`PaddingSpellingsTests`, native arms); `theTextAndStackPaddingSpellingsCompile`, `theSystemDefaultPaddingSpellingsStayAbsent` (guards). Inventory family `padding-spellings`.

## DX-C - the breaking options, not taken

Making `Text`'s and a stack's padding the *same* function would need one of: (1) change `StyledElement.padding(_: Edges<Length>)` to `Edges<Pixels>` (breaks every rem caller and the three `FR-Q` entry points); (2) make `Length` `ExpressibleByIntegerLiteral` (then `Edges(all: 8)` is ambiguous between the two overloads on `Text`; and it blurs `Length.pixels` vs `.percent`); (3) make `Text` a `ProposalElementGroup` (a layout-vocabulary change the `Text` doc comment defers: modifiers return `Self`, divergence 155, and every `Text` modifier would then have two homes). DX-B gives the same *spellings* on both without any of these. Recommendation: stop here; revisit (3) only with the `Text`/`ProposalText` unification.

## Carried (one sentence each, for the shards)

- `docs/rules/tooling.md`, Test harness: a `TestWindow`'s `TimelineView` clock is simulated from the window's first build (`DX-A`): `advance(by:)` alone re-evaluates a periodic timeline; a new timeline-wake path must go through `TimelineStore.scheduler` so the harness can hold it.
- `docs/rules/layout.md`, padding: SwiftUI's padding spellings (`padding(_: Pixels)`, `(_: Edge.Set, _: Pixels)`, `(_: EdgeInsets)`) exist on both vocabularies and lower to the vocabulary's one existing padding (`DX-B`); a new `ProposalElementGroup` modifier must be checked against `Component where Self: ProposalElementGroup` for an ambiguity.
- `docs/rules/decision-prefixes.md`: new row `DX-` -> this document, next unused `DX-D`.
- CLAUDE.md counts: divergences 176 -> 177 live (label 208; 207 may be the sibling's), tests +the counts in the report.
- Record: no `docs/record/` entry written (the orchestrator numbers it); a divergence's record §04 section is owed for 208.
- Human check: none (a layout and a harness change; no look).

## Mutations (each applied to the committed source, the named tests run under `--build-system native`, then restored)

| mutation | reddened |
|---|---|
| MX-A: no simulated wake scheduler | `advanceAloneReevaluatesAPeriodicTimeline`, `oneAdvanceAcrossSeveralEntriesShowsTheLatestAndKeepsGoing` |
| MX-B: `tick()` fires no due wake | the same two |
| MX-C: the window is not put on the simulated clock before its first build | the same two |
| MX-D: fire the held wake without the due-date guard | `advanceAloneReevaluatesAPeriodicTimeline` (the "nothing drew" arm) |
| MX-E: `endFrame` keeps the wake when no timeline is left | `aTimelineThatLeftTheTreeWakesNothing` |
| MX-F: `Edge.Set.insets` reads leading as trailing (and the reverse, two spellings) | `textTakesTheSwiftUIPaddingSpellings`, `aStackAndProposalTextTakeTheSameSpellingsWithTheSameGrowth`, `leadingPaddingPushesTheContentRightOnAStack` |
| MX-G: `StyledElement.padding(_: Edges<Pixels>)` drops the bottom | `textTakesTheSwiftUIPaddingSpellings` |
| MX-H: `EdgeInsets.edges` swaps top and bottom | **green on the growth sums**; `edgeInsetsPutEachInsetOnItsOwnEdge` added and reddens |
| MX-J: no `Component where Self: ProposalElementGroup` overload | the build (`ambiguous use of 'padding'`, `LayoutAuthorityTests`) - observed when first adding the overload |
| MX-M: `StyledElement.padding(_: Edge.Set, _: Pixels)` given defaults | `theSystemDefaultPaddingSpellingsStayAbsent` |
