# 435: a release build's first frame is dominated by the constructed tree value; the default demo is split at `Component` boundaries (`HP-P`; class M, no divergence)

Branch `perf/release-tree-stack`, base master `eb25ea24`. Demo content and tests only, no framework change, no public API, no divergence (242 live, next label 250).

**Why.** Record 427 left the default demo's release first frame open (1,071,216 bytes by its harness, a 1 MiB Windows main thread at its edge). Re-measured at `eb25ea24`: 1,107,040 bytes below `Window.drawFrameIfNeeded` (the stack painted with a pattern, then a window open plus one frame, `lldb` over `MetalUIDemo` in release), and a `ulimit -s` bisect puts the least stack that survives at about 1090 KiB, so `ulimit -s 1024` crashed. Layout and paint peak at about 0.45 MB, system frameworks under 1 KB: it is the **construction of the `Element` value tree, before layout**. The frames, from a backtrace at the deepest point: `demoContent()` 304 KB, the specialised `demoRoot` 302 KB, `Row.init(gap:content:)` 51 KB, closure #1 in `demoRoot` 147 KB, the specialised `ElementBuilder.buildBlock` 142 KB, `TupleGroup.init` 25 KB. The root value is 51,680 bytes (header 5.7 KB, sidebar 10.5, hero 7.6, scroll 9.3, main pane 30.7, body 42.2), so those frames are about six times it: in release the specialised composing functions keep every intermediate copy of the nested generic value alive, and each modifier copies the whole value. `@inline(never)` on the `demo*` functions alone saved 92 KB.

**What.** `DemoHeader`, `DemoSidebar`, `DemoMainPane`, `DemoHeroStack` and `DemoScrollBox` are `Component`s (the remedy record 427 and `PE-K` name), holding their own modifiers, with the body row and the root column left as functions that hold only empty components and the hairline. The demo's state is unchanged (it reads the `demoModel` global where it always did; `CounterPanel` is the same `Component`). A component is layout-transparent: no node, rect or label moved, and no golden was re-recorded (`theDemoFrameMatchesTheValuesRecordedOnMacOS`, the demo capture and replay tests are green unchanged). The root value is 4,720 bytes.

## Numbers (macOS arm64, release)

| | master | this branch |
|---|---|---|
| root value (`MemoryLayout.size(ofValue: demoContent())`) | 51,680 | 4,720 |
| first frame's stack high-water | 1,107,040 | 302,656 |
| least `ulimit -s` that survives | 1090 KiB (1080 crashes, 1100 survives) | 320 KiB (304 crashes) |
| idle frame, element requests | 87 | 87 |
| idle frame, allocations | 19,952 | 19,968 |
| release layout and draw, `setNeedsRedraw` and a tick (us a frame) | 849, 862, 889, 1035, 1041, 1061 (median about 960) | 826, 854, 919, 986, 1639, 1696 (median about 950) |

The release time is a scratch package over `MetalUITesting` (`TestWindow`, 2000 frames after 30 warm-up, six interleaved runs); the machine is bimodal (both builds show 1.6 to 1.9 ms runs), so the medians and minima are what it says: unchanged within noise (minima 849 and 826). Record 427 measured four percent for its components; five components here cost 16 allocations of 19,952, and no element request.

## Tests

`ReleaseTreeStackTests` (two tests). One existing test moved: `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` hard-codes the demo's element ids, and a `Component` is one identity level (opaque to identity), so the header, sidebar, main pane and scroll box ids gained one `child(_, 0)` each; every rect, the 3,053 element count and the modal rows are the same literals. No golden (`theDemoFrameMatchesTheValuesRecordedOnMacOS`, the capture and replay tests) changed. In the full run (7,493 tests) it was the only failure; it passes alone after the id edit.

- `theDefaultDemosRootValueIsAFewKilobytes` pins the root value at 5,120 bytes or less. **Mutations:** the whole demo as on master reads 51,680; `demoBody()` holding `DemoSidebar().content` inline reads 15,272. Both red.
- `anIdleFrameOfTheDefaultDemoCostsWhatItDid` pins an idle frame at 87 element requests and 19,968 allocations or fewer (Darwin). The first version, with the body row a component as well, read 19,973 (3,808-byte root); not making it one saved five allocations for 912 bytes.

`theCensusDemosLayOutBelowOneMebibyte` already lists the default demo (`xrMeasuredDemo("demo")`) and holds it under 1 MiB in a debug build; it stays green and was not touched. It cannot see release.

## Framework experiment (pre-fix demo, not landed)

| candidate | high-water | saving |
|---|---|---|
| master | 1,107,040 | |
| `@inline(never)` on both `ElementBuilder.buildBlock`s and `TupleGroup.init` | 1,107,040 | 0 |
| `Box`'s builder `init` assigning its fields instead of delegating, and `Row`/`Column` passing the closure to it (no `content()` local in the container's init) | 1,057,808 | 49,232 |

The bar was 100 KB with the release time unchanged, so neither landed and no benchmark was run on them. The first is a no-op: the frames that matter are the demo module's own specialisations. The second is real but small; it is worth carrying if a tree has to be split no further. Nothing was boxed.

## What is left

- Any large static tree in an app has the same shape: about 6 times the value in release on the first frame. The remedy is the same split, and `theDefaultDemosRootValueIsAFewKilobytes` is the pin for the demo only.
- The Windows x86-64 figures are not measured.
