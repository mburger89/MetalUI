# Record 222: frame timing and signposts (Alloy gap G7)

Branch `feat/frame-signposts` (master `9116adff`). Rulings `FP-A`..`FP-H` in `docs/superpowers/2026-11-07-frame-timing-decisions.md` (new prefix; `FS-` was taken by the retained-translation rulings; next `FP-I`). Class `M`; no divergence added (209 live, next label 226). Guide `docs/frame-timing.md`.

## 1. What was built

`FrameTiming` (a ring of `FrameTimingSample`, `onFrame`, `onPresented`, optional `OSSignposter`), `Window.frameTiming`, the defaulted `WindowRenderer.setPresentationObserver(_:)`, Metal's `addPresentedHandler` path, the headless renderer's scripted display. Tests `Tests/MetalUITestingTests/FrameTimingTests.swift` (portable: macOS, Linux, Windows; the allocation pin is Darwin-only like `countAllocations`).

## 2. Deviations from the approved design

- **`Frame.swift` was edited** (a `timing` property and three one-line stamps): the phase boundaries live inside `Frame.renderOutsideDispatch`, and every non-editing alternative (hooking `GlyphAtlas.beginFrame`, `animationStore.transitions.afterLayout`) would have stamped by accident of another call's position.
- **`inputTimestamp` is not always the platform's**: a platform timestamp on a different clock (SDL, the harness) cannot be compared with `now()`, so it falls back to the receive time (`FP-G`); `inputReceived` is always kept.
- **A clean event is not an input** (`FP-G`): the design said "earliest input event handled since the previous frame"; a mouse move that dirtied nothing would otherwise stamp a later animation frame with seconds of "latency".
- **`presented` is delivered through a defaulted protocol method** (`FP-F`), not a stored property on the renderer (a protocol extension cannot hold state).

## 3. Mutations (each applied alone, `swift test --no-parallel --filter FrameTimingTests`, reverted)

| Mutation | Reddened |
| --- | --- |
| `stampLayoutEnd()` call removed from `Frame.renderOutsideDispatch` | `aKeyThenATickRecordsOneOrderedSample`, `aFrameThatBuildsTwiceKeepsTheLastBuildsStamps`, `signpostsAreOnlyEmittedWhenAskedFor` |
| `stampPrepaintEnd()` call removed | the same three |
| `commitFrame` does not write the ring | nine of the ten (everything that reads `samples`/`last`) |
| a key mapped to `.text` | `aKeyThenATickRecordsOneOrderedSample`, `inputAttributionIsTheEarliestDirtyingEvent`, `inputKindsFollowTheEventFamily`, `signpostsAreOnlyEmittedWhenAskedFor` |
| `settleInput` ignores `dirtied` | `inputAttributionIsTheEarliestDirtyingEvent` |
| a later event replaces the pending one | `inputAttributionIsTheEarliestDirtyingEvent` |
| `.scrollWheel` mapped to `.pointer` | `inputKindsFollowTheEventFamily` |
| the one-second plausibility window removed | `aPlatformTimestampOnOurClockIsUsedAndOtherwiseTheReceiveTime` |
| ring slot clamped instead of wrapped | `theRingWrapsAndKeepsTheNewest` |
| `samples` read in slot order | `theRingWrapsAndKeepsTheNewest` |
| `deliverFrame` before `commitFrame` | `onFrameRunsAfterTheFrameAndItsWriteIsNotStale` |
| layout stamp taken once (first build only) | `aFrameThatBuildsTwiceKeepsTheLastBuildsStamps` (the first spelling of this test was green: its only assertion was order, which first-build stamps keep; it now logs each build's clock) |
| presentation token not offset by the timing's base | `presentationReachesTheRightFrameLater` (first spelling green: it never reattached a timing that had recorded frames; the detach/reattach arm was added) |
| `onPresented` not called | `presentationReachesTheRightFrameLater` |
| `emitsSignposts` always `false` | `signpostsAreOnlyEmittedWhenAskedFor` |
| the ring write allocates | `recordingAndNotRecordingAllocateTheSame` |
| the disabled path allocates | `recordingAndNotRecordingAllocateTheSame` |

The first spelling of `ordered(_:)` used `<=` and `commitFrame` clamped a missing stamp up to its neighbour, which hid every removed-stamp mutation; both were removed (strict `<`, no clamp) before the table above was taken.

## 4. Results (2026-11-07)

- Root, `swift package clean`, `--build-system native --build-tests`, unfiltered `--no-parallel`: **5344 tests in 14 suites passed** (428 s, then 349 s on the final commit), `FR-J no-argument frame: succeeded=true`. One red on the first run, `everyFrameChannelIsClassified` (`Frame.timing` needed a `frameChannels` row, `.frameLocal`), fixed in the second commit.
- Portable Docker `metalui-portable:latest` from `git archive`: 816 + 9 + 16 + 73 + 68 + 49 + 286 + 154 + 24 passed. The first Linux run was red on two of the new tests: an `@Observable` write reaches a Linux window one main-actor hop later (`HT-S`), so the tests that need a synchronous dirtying write through a captured `@State` binding.
- `Backends/SDL` builds with AccessKit flags; `SDLTextGradient|ReplayFixture|SDLClipMask|SDLGroup`: 40 and 15 passed. `SDLWindowRenderer` is unchanged: SDL_GPU reports no presentation time, so `presented` is `nil` there (`FP-F`).
- Not run: a real Instruments/`xctrace` capture of the signposts and a real Metal `presentedTime` (an agent cannot; human check below).

## 5. Owed to a person

Open `Instruments` with the os_signpost instrument on the demo run with `METALUI_SIGNPOSTS=1`, type in a text field and scroll a list, and confirm `Input→Frame`, `Frame`, `Layout`, `Prepaint`, `Paint` and `Present` appear under `com.metalui` and that a `FrameTiming.onPresented` callback reports `presented` after `commit` on a real display.
