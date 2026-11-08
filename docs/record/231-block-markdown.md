# Record 231: the block Markdown parser (Alloy gap G2, PRs 1 and 2)

Branch `feat/markdown-parser` (master `b0fa5ae5`). Rulings `BM-A`..`BM-D` in `docs/superpowers/2026-11-07-block-markdown-decisions.md` (new prefix; next `BM-E`). Class `M`; no divergence added or retired. Record 230 is the symbol-images line in flight; this took 231. Scope: the pure target and its streaming append, i.e. plan PRs 1 and 2 as one branch. **The view (`MarkdownView`, `MarkdownBlockView`, the theme, code fences, tables, the demo and human checks) comes next as PRs 3 and 4 and is not in this record.** No guide (a guide needs compiled mirrors); usage is in `docs/api-overview.md`.

## 1. What was built

The portable target `MetalUIMarkdown` (imports nothing; own library product; `@_exported` by `MetalUI`): `MarkdownDocument` (`init()`, `init(parsing:)`, `append(_:)`, `blocks`, `version`), `MarkdownBlock` (`id`, `kind`, `init(id:kind:)`), `MarkdownBlock.Kind` (`paragraph`, `heading(level:text:)`, `codeBlock(language:code:isClosed:)`, `blockQuote`, `list(ordered:start:tight:items:)`, `thematicBreak`, `table(alignments:header:rows:)`), `MarkdownTableAlignment` (`none`, `left`, `center`, `right`), and the `package` counters `MarkdownParseStats` (`bytesScanned`, `bytesCompared`, `blocksFinalized`, `bytesCopied`, `reset()`). `parseWhole(_:)` (`package`) is the one-pass reference the streaming path must equal.

Files: `MarkdownTypes.swift` (public types, the counters), `BlockParser.swift` (a port of cmark-gfm's `blocks.c` onto an index-linked arena: container matching, new block starts, the line's text, finalisation with the tight/loose rule; the GFM table extension; output to values), `MarkdownDocument.swift` (the tail, finality, copy-on-write box). Tests: `Tests/MetalUIMarkdownTests` (25 tests, 6 suites, portable) and, Darwin only, `Tests/MetalUITests/MarkdownBlockOracleTests.swift` (3 tests). Probe: `docs/probes/foundation-markdown-blocks.swift` (arms B1-B30, recorded output in the header).

## 2. Probe readings that set rules (macOS 27.2)

| Reading | Rule |
| --- | --- |
| B1-B3: a soft break is a `" "` run (inline intent 64), a hard break (two spaces or a backslash) a `"\n"` run (128) | paragraph lines are kept joined with `"\n"`; the view maps a soft break to a space by default (PR 3). MetalUI's inline parser keeps a break as written and keeps the spaces before a hard break, so the view maps soft breaks and trims first (the oracle's `plain` does exactly that) |
| B4: task lists are plain paragraph text | v1 does not parse them (`BM-B`) |
| B5-B6b: a long row is cut, a short row's missing cell has no run, "no alignment" reads as left | rows padded or cut to the header; `.none` kept in the API |
| B7-B8: loose and tight lists carry identical intents | tightness is invisible to the oracle; pinned by test 1 |
| B9: the language hint is the whole info string | `language` is its first word |
| B14, B22, B23: empty items, fences and cells have no run | the oracle drops empty containers on both sides; an empty item stays `[]` so ordinals survive |
| B17: a table starts at the paragraph's last line | the earlier lines stay a paragraph; the table takes the next id |
| B18-B21: a failed delimiter row poisons the paragraph; an indented or lazy delimiter-looking line makes no attempt | `tableRefused` on the paragraph node; the mechanism in cmark-gfm is not known, the flag reproduces every reading |

## 3. Oracle disagreements and rulings

None found. Test 8 compares kind trees, heading levels, list ordinals, code text and language, table alignments and non-empty cells and paragraph plain text with Foundation `.full`: **0 disagreements over all 28,561 four-line sources of thirteen line kinds (1.3 s) and 20,000 seeded longer sources (1.0 s)**. Two disagreements were found and fixed while building the oracle, both parser rules the first corpus run exposed: the table poisoning above (`a / |-|-| / |-|-|`), and normalising an empty container on both sides. The rulings against Foundation are normalisations, not differences in what is drawn (`BM-B` items 2, 3 and 5). The plan's oracle mutation "drop the loose rule" cannot be seen by the oracle (reading B7/B8); it is applied to test 1.

## 4. Test 4 reached back: the plan's finality rule needed a ruling

Streaming the corpus a scalar at a time found several shapes in which a block that starts before the last block was not final, **all caused by a half-typed last line**, never by a complete line (`BM-C`): `-` is a list until it is `-|-` (a lazy continuation of the paragraph above), `#` is a heading until `#a`, `1` then `1.` can join the list above after a blank line, `|` is not a table row until `|-|-|` (so the table above ended), and `|-` turns a paragraph's last line into a one-column table before `|-|-|` unmakes it. Ruling (the plan's own: keep the construct in the tail): **while the text ends in a line with no newline whose bytes so far are only block-structure characters, the block before the last is parsed again too.** After the ruling the corpus agrees; before any rule, 275 of the 28,561 exhaustive sources failed (a first, too narrow rule that kept the block above only when the last block started on the half-typed line still failed 160).

- Corpus: the plan names 12 line kinds (12^4 = 20,736) but lists 13; all 13 are used, **28,561 sources**, each parsed whole and streamed at 1, 3 and 7 scalars (85,683 streamed document builds) plus 6,000 seeded sources of 2-8 lines over 57 richer line kinds (tabs, CRLF, non-ASCII, `~~~`, ordered lists, escaped pipes).
- **Runtime in a debug build: 4.0 s (5.2 s with the suite) for the exhaustive test on a quiet machine, 7.4 s under contention**, far below the 60 s stop condition.

## 5. Counted work (debug, `--no-parallel`)

| Pin | Measured |
| --- | --- |
| One token (4 bytes) after k = 1, 10, 1000 final blocks, last block 23 bytes | `bytesScanned` 27, 27, 27 (tail + token) |
| A letter line after 500 blocks and a 15-byte block above it ("T" then "hen") | 4 (the line and the token) |
| A structure line ("1" then ".") after the same | 19 = 15 + 2 (the block above and its blank line) + 2 |
| 20 blocks finalised by 20 appends | `blocksFinalized` 20 |
| Copy of a 1000-block document, then one append | `bytesCopied` > 0 and at most the 17-byte tail, the view's copy unchanged; an unshared append copies 0 |

## 6. Mutations (each applied alone, in place after committing, whole suite of the scratch two-target package, restored with `git checkout`; log `scratchpad/mut/results.log`)

| Mutation (spelling) | Reddened |
| --- | --- |
| setext branch dropped (`lev > 99`) | `setextHeadingsTakeTheWholeParagraph`, `aListInterruptsAParagraph...`, `aBlockKeepsItsIdWhenItChangesKind...`, `streamingEqualsWholeParsingOverRandomLongerSources`; oracle: both corpora |
| a list interrupts a paragraph with any start number (`if start != 1` deleted) | `aListInterruptsAParagraphOnlyWhenItStartsAtOneAndHasText`, `theContentColumnDecidesWhatBelongsToAnItem`; oracle: the random corpus |
| content column = marker column (item prefix) | 7 tests, `theContentColumnDecidesWhatBelongsToAnItem`, `tabsCount...`, `lazyContinuation...`, `listsAreTightOrLoose...`, `setext...`, `nestedBlocksNumberThemselves...`, the CRLF test |
| a tab counts as 1 column (`firstNonspaceColumn += 1`) | `tabsCountToTheNextMultipleOfFour` only |
| a delimiter row with a different column count accepted | `aHeaderWithoutAMatchingDelimiterRowStaysAParagraph`, both streaming corpora |
| table poison dropped | `aHeaderWithoutAMatchingDelimiterRowStaysAParagraph`; oracle: both corpora |
| tight/loose rule dropped (always tight) | `listsAreTightOrLooseAndKeepTheirStartNumber`, `theContentColumnDecidesWhatBelongsToAnItem`; **oracle stays green (3 passed): the finding of reading B7/B8** |
| ordered list start ignored | oracle: the random corpus (the exhaustive one has only `1.` lines) |
| tail starts at the last line, not the last block | 7 tests incl. both streaming corpora, the id test, `appendingATokenScans...` |
| the last block is finalised too (first spelling trapped: `parsed[keep]` out of range at `keep = parsed.count`, which is a red run but a poor mutant; re-spelled with `cut = tail.bytes.count`) | 8 tests incl. both streaming corpora |
| half-typed line trusted (provisional rule deleted) | `aHalfTypedStructureLineKeepsExactlyOneBlockAboveItInTheTail`, both streaming corpora |
| re-parse from 0 (the tail is never cut; the finalisation loop skips blocks already moved) | `appendingATokenScansOnlyTheTailAndTheToken`, `aHalfTyped...`, `divergingFromACopyCopiesOnlyTheTail`, `blocksAreFinalisedOnce...`, both streaming corpora |
| copy-on-write check removed (`if false`) | `divergingFromACopyCopiesOnlyTheTail` (the "instrument works" arm: nothing was copied) |
| hash-based ids | the id test, the CRLF test, `oneShotInitialiserEqualsWholeParsing`, both streaming corpora (2204 issues) |

## 7. Results

2026-11-07, macOS 27.2 arm64, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

- `swift package clean`, `swift build --build-system native --build-tests` (458.97 s) and `swift test --build-system native --no-parallel`, unfiltered: `Test run with 5562 tests in 25 suites passed after 455.455 seconds.` and `FR-J no-argument frame: succeeded=true deprecations=2`. Master's printed 5534 in 18 suites plus the 25 portable tests in 6 suites and the 3 oracle tests in 1 suite is 5562 in 25. No guard was added (the guard tally is unchanged). The run under `METALUI_VERIFY_RETAINED=1` was not repeated: nothing here touches retained replay.
- `MetalUIMarkdownTests` alone: `Test run with 25 tests in 6 suites passed after 5.191 seconds.` (debug, `--no-parallel`); `MarkdownBlockOracleTests`: `Test run with 3 tests in 1 suite passed after 2.371 seconds.`
- `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- Portable container: `metalui-portable:latest` (Linux, Swift 6.4), fed by `git archive HEAD` over stdin (`docker run --rm -i`, no mount, no volume): `swift build --build-tests` complete (368.19 s) and `swift test --skip-build --no-parallel` ran `MetalUIMarkdownTests` with the others: `Test run with 25 tests in 6 suites passed after 4.020 seconds.` (the same output: 910 in `MetalUITestingTests`, 9, 16, 73, 68, 53, 286, 154, 24 and 45, all passed). The exhaustive streaming corpus runs on Linux too. Windows could not be run locally: the new target and tests are in the always-declared manifest list, so `root-windows` builds and tests them without a workflow change.

## 8. Hand-off to PRs 3 and 4

- The inline parser keeps a line break as written and the spaces before a hard break (section 2); the view must map soft breaks (default a space) and trim hard-break spaces before `parseInlineMarkdown`.
- `MarkdownDocument` has no storage identity yet; the view's O(1) equality (plan section 3) needs `version` plus an identity; add a `package` id in PR 3 rather than widening the public API now.
- Streaming a long single line that starts with structure characters (a thematic-break line of hundreds of dashes) keeps the block above in the tail for that line; the view owes nothing for it, but it is the one place the per-token cost is not O(last block).
