# Record 225: the code buffer (Alloy gap G1, PR 1)

Branch `feat/code-buffer` (master `4d4c59db`). Rulings `CV-A`..`CV-I` in `docs/superpowers/2026-11-07-code-view-decisions.md` (new prefix; next `CV-J`). Class `M`; no divergence added or retired. Records 223 and 224 are other lines in flight; this took 225. No guide (a guide needs compiled mirrors); usage is in `docs/api-overview.md`.

## 1. What was built

The portable target `MetalUICodeBuffer` (imports only `Observation`; own library product; `@_exported` by `MetalUI`): `CodeBuffer` (a `@MainActor @Observable` class), `CodeSnapshot`, `CodeEditCursor`, the edit and selection value types, `RopeStats.nodesVisited`. Files: `Summary.swift` (summaries, chunks, the counter), `Rope.swift` (the B-tree), `CodeBuffer.swift`, `CodeSnapshot.swift` (conversions, lines, find), `CodeEditCursor.swift`, `CodeTypes.swift`, `ExternalDiff.swift`. Tests: `Tests/MetalUICodeBufferTests` (45 tests, 4 suites; portable: they run in the Linux and Windows root jobs, which build and test every declared target).

## 2. Numbers (macOS arm64, debug)

| Measure | Value |
| --- | --- |
| Node | final class, 104 bytes of fields (height, two array refs, 64-byte `Summary`) |
| Branching | 16 max, 12 fill |
| Chunk | 768 max, 512 target, neighbours merge when they fit 512; slot 24 bytes (array ref + 14-byte `ChunkSummary`) plus a 32-byte array header |
| Storage / text, 2k lines | 1.140 built, 1.168 after 4000 random edits (average chunk 461 bytes) |
| Storage / text, 100k lines | 1.135 built, 1.154 after 4000 random edits (average chunk 497 bytes) |
| Tree height | 1 at 1k lines (80 KB), 3 at 100k lines (4 MB, 6771 chunks, ceil(log2) = 13) |
| Nodes visited per keystroke edit (insert or delete) | 1k lines: max 18, mean 14.0; 100k lines: max 39, mean 28.0 (pinned: max <= 4 x ceil(log2 chunks); mean difference <= 12 per extra level) |
| External edit, two small hunks | 1k lines: 30 nodes; 100k lines: 60 (pinned: difference <= 24 per extra level, and <= 8 x ceil(log2 chunks)) |
| Build | one scan, each node created once (`nodesVisited` after build equals the node count) |

## 3. Deviations from the plan

- **Chunk size 768/512, not 64-256** (`CV-B`): the plan's chunk size put per-chunk overhead (header, slot, summary) near 0.3 of the text, past its own 1.3x budget.
- **Added API** beyond the agreed proposal: `CodeBuffer.replaceSelections(with:origin:)` (the typing primitive; without it a typed caret would have to be moved with a selection write, which ends coalescing), `primarySelection`, `revealSerial`, `undoByteLimit`, `CodeSnapshot.text`, `utf8(in:)`, `lineRange(_:)`, `utf8Count`, `scalarCount`, `utf16Count`, `longestLineScalars`, `utf16Offset(ofUTF8:)`, `utf8Offset(ofUTF16:)`, `byte(at:)`, `isScalarBoundary(_:)`, `CodeLineEnding.text`, `CodeFindOptions` as an `OptionSet` (`caseInsensitive`, `wholeWord`), `CodeSelection(caret:)`/`isEmpty`, public memberwise inits. `CodeBuffer.hadInvalidUTF8` is a `let`. `lineEnding` and `isReadOnly` are plain observed vars. `CodeBias` is `before`/`after`.
- **`replace` traps on a bad range** (a precondition) while the external entry points throw `.invalidRange` (the proposal had one error type for the throwing calls only).
- **`applyExternalEdits` with only no-op edits** returns a transaction id and changes nothing; an undo entry that merely touches an external range is dropped (closed-interval overlap, conservative).
- **No Foundation anywhere** in the module, so `String(validating:)` (macOS 15) is replaced by a `UTF8` decode loop; the platform floor is macOS 14.
- Observation off Darwin: `@Observable` in a Foundation-free module is used by `MetalUI` itself on Linux and Windows; no stop condition arose (Linux container run, section 5).

## 4. Mutations (each applied alone to a scratch copy of the target and its tests, whole target suite, reverted from a pristine copy; log `scratchpad/mut-results.log`)

| Mutation | Reddened |
| --- | --- |
| UTF-16 counted as scalars (`Summary.of`) | `buildFromBytesAndFromAStringAgree`, `conversionsAgreeWithTheOracleOnTheFixture`, `randomEditsMatchAStringOracle` |
| a cut inside a scalar (`chunkify` skips no continuation byte) | `randomEditsMatchAStringOracle`, `buildFromBytesAndFromAStringAgree`, `chunkBoundariesNeverSplitAScalarOrACRLF`, `buildTouchesEachNodeOnceAndIsLinear`, `aKeystrokeVisitsLogarithmicallyManyNodes`, `nodeStorageStaysWithin1Point3TimesTheText`, `aSnapshotIsUnchangedByLaterEdits` |
| CRLF split across chunks at build (`chunkify` ignores the CRLF rule) | `chunkBoundariesNeverSplitAScalarOrACRLF`, `buildFromBytesAndFromAStringAgree`, `buildTouchesEachNodeOnceAndIsLinear`, `aJoinedCRLFIsRepairedAcrossChunks`, `aKeystrokeVisitsLogarithmicallyManyNodes`, `nodeStorageStaysWithin1Point3TimesTheText` |
| CRLF repair after an edit removed (`fixCRLF` disabled) | `aJoinedCRLFIsRepairedAcrossChunks` only |
| post-edit coordinates emitted (`range:` of the event) | `eventsCarryPreEditCoordinatesAndPoints`, `externalEditsRunHighestFirstInPreEditCoordinates`, `mapCarriesAnOffsetThroughTheLog`, `randomEditsMatchAStringOracle` |
| ascending application order of external edits | `externalEditsRunHighestFirstInPreEditCoordinates`, `replacementDiffsIntoFewHunks`, `replacementOfARandomRewriteIsExact` (the run then trapped) |
| copy-on-write mutates in place when shared | `aSnapshotIsUnchangedByLaterEdits` |
| inside-span bias flipped (distance from the end instead of the start) | `selectionsMoveWithEdits`, `aCaretInsideAReplacedSpanKeepsItsDistanceWhenTheTextIsTheSameSize`, `externalEditsMoveCaretsLikeTheSelectionRule` |
| overlapped undo entry kept | `anUndoStepThatOverlapsAnExternalEditIsDroppedWithEveryOlderOne` (first spelling did not compile: the closure took `$0` and the replacement had none; reran with `{ _ in false }`) |
| `oldEndPoint` taken from the new text | `eventsCarryPreEditCoordinatesAndPoints` |
| external edit validation scans the whole text (naive spelling of the perf pin) | `anExternalEditOfASmallHunkIsIndependentOfTheLineCount` |
| version rises by 2 | `randomEditsMatchAStringOracle` (trap in the replay) |
| cursor never resyncs | the run trapped in `aSlowCursorIsToldToResync` |
| `.stale` check removed | `staleVersionIsRefused` |
| `hadInvalidUTF8` always false | `invalidUTF8IsRepairedAndReported` |
| CRLF never detected | `linesAndPointsHandleCRLFAndTheLastLine` |
| chunk target 64 bytes | `buildTouchesEachNodeOnceAndIsLinear`, `nodeStorageStaysWithin1Point3TimesTheText` |
| undo does not restore selections | `typingCoalescesIntoOneStepAndRestoresTheSelection` |
| `breakUndoCoalescing()` does nothing | `typingThatIsNotAdjacentOrIsInterruptedStartsANewStep` |
| a merged chunk loses its second half | the run trapped (precondition in `replace`) |

The scratch copy (a two-target package of the same sources) was used because another build was running and a worktree copy of the full package would not fit the disk; the mutated files are byte-identical to the committed ones apart from the mutation.

Findings from the first runs: the oracle's `rows` used `String.split(separator: "\n")`, which treats CRLF as one `Character` and miscounted lines (a test bug, fixed with a byte split); two tests deleted one byte at a position inside a multi-byte scalar (the precondition caught them); `versionsRiseByExactlyOnePerEvent` first expected an undo after an external edit that overlapped the undo step, which is correctly dropped.

## 5. Results (2026-11-07)

See the commit message of the record's final commit and the summary lines pasted in section 6 when taken.
