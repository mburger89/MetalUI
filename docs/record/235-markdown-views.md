# Record 235: the Markdown views (Alloy gap G2, PRs 3 and 4)

Branch `feat/markdown-views` (master `1fa45020`). Rulings `BM-E`..`BM-J` in `docs/superpowers/2026-11-07-block-markdown-decisions.md` (next `BM-K`). Class `M`; no divergence added or retired (labels untouched). Follows record 231 (the parser and streaming append). Records 233 and 234 are held by branches in flight; this took 235 (re-check `README.md` at merge).

## 1. What was built

`MarkdownView` (`init(_ document:)`, `init(_ source: String)`, `markdownTheme(_:)`, `codeHighlighter(_:)`), public `MarkdownBlockView` (`init(_ block:)`, the same two modifiers), `MarkdownTheme` (a plain value) and `MarkdownSoftBreak`, `MarkdownCodeHighlighter` and `MarkdownCodeRun`, in `Sources/MetalUI/Markdown/`; the `package` `MarkdownDocument.identity`; the demo `METALUI_MARKDOWN_DEMO=1` (`Sources/MetalUIDemoContent/MarkdownDemo.swift`, its builder `buildTheMarkdownDemo()` in `everyProductionTreeBuildsOnAOneMegabyteThread`); human-check group BM (BM1-BM5). Tests: `MarkdownViewTests` (7), `MarkdownStreamingViewTests` (5), `MarkdownDemoTests` (1), support in `MarkdownViewSupport.swift`.

**API against the promise:** every promised spelling is as built. Additions: `MarkdownTheme` also has `tableScrolls`, `listItemSpacing`, `listMarkerSpacing`, `quotePadding`, `showsCodeLanguage`, `codeCaptionFont`, `codeForeground`, `tableColumnSpacing`, `tableRowSpacing`; `MarkdownSoftBreak` is the type of `softBreak`; `MarkdownCodeHighlighter` is **not** `@MainActor` (the promise had no isolation). **Two defaults differ from the plan: `codeWraps` is true and tables do not scroll** (section 3), and **a code block is a `.contain` group, not `.combine`** (`BM-I`).

## 2. Counted work (debug, `--no-parallel`, portable text system)

| Pin | Measured |
| --- | --- |
| One token on the last paragraph of the last of 10 or of 200 replies (20 blocks each) | `contentEvaluations` 2 and 2 (the reply's `MarkdownView` and the one changed block); the rest skipped |
| The same, bytes the text system measured, reply with no inline markup | 100 and 100 (the changed 50-byte paragraph, twice) |
| The same, reply with rich text in its unchanged blocks | 2,200 and 2,200: the layout of the changed reply measures its rich blocks again (a rich `Text` has no layout-memo key); independent of the transcript, O(rich blocks of that reply) |
| Last block keeps its accessibility id across tokens | yes at both sizes |
| A token on an open fence of 69 and of 485 lines (last chunk 5 lines both) | equal bytes shaped; the longest measured string is at most 32 lines |
| `MarkdownView(String)` grown by appended text, 61 blocks | `bytesScanned` at most the tail plus the token; `bytesCompared` equal to the old source's length |
| Settled transcript, 4 frames, nothing changed | `retainedHits` > 0, `retainedIneligible` 0, `contentEvaluations` 0, `contentRefusals` 0 |

## 3. Stop conditions

1. **Hit: a horizontal scroller swallows a vertical wheel.** Measured (BM2): a vertical wheel over a code block in a horizontal `ProposalScrollView` scrolls nothing, with long lines or with lines that fit. Ruled as the plan said: `codeWraps = true` by default; and tables likewise do not scroll by default (`tableScrolls` false; cells wrap). The scroller is carried (`codeWraps = false`, `tableScrolls = true` give it back, the swallowed wheel pinned wrong on purpose). `defaultScrollAnchor(.bottom)` pinning is unharmed in both arms.
2. **Rich text re-measure, partly hit.** The cost is not the changed paragraph's (measured twice per token) but the unchanged rich blocks of the *changed reply*, re-measured by its layout (section 2). It is independent of the transcript and no keyed leaf was added (`BM-J`). The release timing of a 4 KB rich paragraph is in section 6.
3. `.equatable()` replay refused for an unplanned reason: **found and fixed, not a framework limit.** A component nested inside an equatable component's memoized value is evaluated by the layout recursion each frame; the highlighter ran three times for an unchanged fence until every nested component (quote, list, item, fence, chunk, table) was itself `.equatable()` (`BM-E`).
4. Other reasons for stopping: none. `MetalUIMarkdown` still imports nothing.

## 4. Findings

- `.combine` with a label drops the code from the accessibility tree (one node, label the language, no value); a code block is `.contain` (`BM-I`).
- The plan's replay mutation premise ("a subtree under a custom environment key cannot be replayed") holds only for an **uncomparable** value: a custom key whose value is `Equatable` (the theme) is compared (`EE-F`) and stays replayable. The theme is still a stored value (`BM-G`).
- `fixedSize` on the code column, the chunk and the table cells was **redundant**: the horizontal scroller proposes no width, so dropping it reddened nothing; it was deleted, not kept as an unexercised guard.
- The demo reply is also the tour: a test pins that it holds every block kind.

## 5. Mutations (each alone, in place after committing, whole `Markdown` filter of the native debug suite, restored with `git checkout`; log `scratchpad/mut.log`)

| Mutation (spelling) | Reddened |
| --- | --- |
| `.accessibilityAddTraits(.isHeader)` dropped | `aHeadingIsAnAccessibilityHeadingAndALinkOpensThroughOpenURL` |
| `request.link = nil` after `markdownRunRequest` | the same test |
| hard-break spaces not trimmed | `softBreaksAreSpacesByDefaultAndHardBreaksTrimTheirSpaces` |
| `MarkdownView` stack spacing 0 | `blocksAreSpacedByTheThemeAndNestedListsAndQuoteBarsFollowIt` |
| quote bar in an `HStack` beside the content | the same test |
| runs sliced by `Character` (the chunk's `slice`) | `aCodeFenceIsABoxOfItsLinesAndRunsColourTheirBytes` |
| default `codeWraps` flipped to false | the same test |
| table alignment ignored (`.leading`) | `aTableAlignsItsColumnsByTheDelimiterRow` |
| table scroller dropped | `aTableWrapsByDefaultAndScrollsWhenTheThemeAsks` |
| `.equatable()` dropped from the blocks in `MarkdownView` | `aTokenCostsTheLastBlockWhateverTheTranscriptHolds` |
| ids by `\.self` (hashed from the block) | the same test, `appendingToAnOpenFenceShapesOneChunk` |
| `linesPerChunk` 1,000,000 (one `Text` per fence) | `appendingToAnOpenFenceShapesOneChunk` |
| prefix compare skipped in `MarkdownSourceMemo` | `aSourceStringGrownByPrefixAppendsAndAReplacementReparses` |
| fence `==` without the highlighter identity | `theHighlighterIsCalledOncePerChangedFenceAndSeesWhetherItClosed` (its first spelling **stayed green**: the replacement instance was tried in a fresh window with no memo; the test now swaps it in one window) |
| theme in a custom key with an uncomparable value | `aSettledTranscriptReplaysItsUnchangedBlocks` (hits 0, ineligible > 0), `aTokenCostsTheLastBlockWhateverTheTranscriptHolds` |
| theme in a custom key with an `Equatable` value | **green** (finding above) |
| `fixedSize` dropped (chunk, column, table cells) | **green**, deleted (finding above) |
| a table row removed from the demo script | `theDemoReplyHoldsEveryBlockKindAndTheHighlighterAnswersValidRuns` |

## 6. Results

2026-11-07, macOS 27.2 arm64, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, shared machine.

- `swift package clean`, `swift build --build-system native --build-tests` (170 s), `swift test --build-system native --no-parallel`, unfiltered: `FR-J no-argument frame: succeeded=true deprecations=2` and `Test run with 5600 tests in 26 suites passed after 355.550 seconds.` (record 231's 5562 in 25, plus 13 tests of this branch and the master changes merged since). With `METALUI_VERIFY_RETAINED=1`: `Test run with 5600 tests in 26 suites passed after 322.484 seconds.` (the count pins are `.enabled(if: !rsVerifying)` and count while skipped). No guard added.
- Portable container `metalui-portable:latest` (Linux, Swift 6.4), `git archive HEAD` over stdin to `docker run --rm -i`: `swift build --build-tests` complete (62.92 s); `Test run with 923 tests in 11 suites passed` (`MetalUITestingTests`, was 910), then 9, 16, 73, 68, 53, `MetalUIMarkdownTests` 25 in 6 suites, 286, 164, 24 and 45, all passed. The new view tests use `harnessTextSystem` and no `AttributedString(markdown:)`.
- `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- **Timing (not pinned), the plan's rich-text stop condition:** `METALUI_MEASURE_MARKDOWN=1 swift test -c release --filter theCostOfATokenOnA4KBRichParagraph`: **3.8 ms per streamed token for the whole frame** (build, layout, paint, headless renderer, portable text system) on a 4,136-byte paragraph with bold, code, italic and a link, on a shared Mac. The re-measure's own share was not separated, but the whole frame is already past the plan's 1 ms line for the measure alone, so **the stop condition is treated as hit: a keyed leaf for rich `Text` (`IV-` owes a key and a covering test) is proposed as its own ruling and was not added here** (`BM-J`). Windows could not be run locally; the new tests are in the always-declared manifest list.

