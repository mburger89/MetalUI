# 427: the debug stack a layout recursion and a `content` getter chain use (`HP-O`)

Class `M` (MetalUI-only, no behaviour change), no divergence row, no public API. Branch `fix/debug-layout-stack-depth`, base master `3de15d73`. Follows record 419's "Fixed after the Windows job": `everyReferenceHeldInStateIsClassified` died on Windows (`c00000fd`) in the `requestGroupLayout` recursion under `ControlsDemo.content` because a 1 MiB worker thread cannot hold the controls demo's first frame in a debug build (1,543,888 bytes by `StackMeter`, macOS arm64).

## How the stack was attributed

`StackMeter` gives one number per frame. To split it, a temporary patch (not committed) recorded, at the deepest sample, the frame chain with libunwind's `_Unwind_Backtrace` and `_Unwind_GetCFA`: the difference between two consecutive CFAs is one function's frame, dynamic allocas included (the `sub sp` in the object file is not: a generic function at `-Onone` `alloca`s a slot for every value of an unknown type, and those are most of the bytes). Each row below is that function's own frame. A frame is quoted with the size `S` of the value it is about, because **nearly every big frame is a small number of copies of one value**: `Component.requestGroupLayout` is 1.0 `S` of the component's `content` (78,912 B for the controls demo's 78,488 B `content`), a container's `init` 2 to 3 `S`, a `content` getter 2 `S`, an initialiser of a struct about 4 `S` of the struct (a mini-experiment: any `init` of a 1,048-byte struct is a 4.3 KB frame, a static function returning it 1 to 2 KB; a delegating `self.init` is another full frame).

Why the numbers are what they are: an element's value is large (`Text` 1,032 B, `Button<Text>` 3,914, `Toggle` 4,993, `Picker` 4,922, `Stepper` 10,328; `Style` 178, `Decoration` 224, `Handlers` 480 inside every `Box`), a tree is one value of the product of its parts, and `-Onone` gives every temporary its own slot, never reusing one.

### The controls demo's first frame, 1,543,872 bytes, by frame (before)

| frame | bytes | what it holds |
|---|---|---|
| `Stepper.control()` + `init(label:…)` + two delegating `init`s + `Stack.init` + its closure | 232,608 | a 10 KB `Stepper` four times in each of three initialisers; `control()`'s ten `Box` temporaries |
| `swiftUIVocabularyForm` closure, `HStack.init`, `VStack.init`, the function; the same four for `swiftUIVocabularySection` | 458,000 | 28.5 KB and 35.3 KB values, 2 to 3 `S` per level |
| `ControlsDemo.content` getter, its closure and `Row.init` | 592,192 | the 78.5 KB row, 2.0, 2.5 and 3.0 `S` |
| `Component.requestGroupLayout` | 78,912 | `var materialized = content`, 1.0 `S` |
| `Element.requestGroupLayout`, `ModifiedContent.requestLayout`, `Frame.renderOutsideDispatch`, the window's closure and `buildAndAdoptFrame` | 31,216 / 32,288 / 39,488 / 27,744 / 26,160 | the root and its layout, copied |

The layout recursion itself (`requestGroupLayout` and `requestLayout` frames) was a small part of the controls demo; the `content` getter chain under it was most. The per-level cost of the recursion is real and is what an app that nests a few hundred levels of `Component`s pays, so both were reduced.

### One nesting level of layout (a `Component` over a `Column` of six `Button`s, 24,443 B of `content`), per level

| frame | before | after |
|---|---|---|
| `Component.requestGroupLayout` | 24,688 | 24,688 |
| `Component.finishComponent` | 32,448 | 8,016 |
| `Element.requestGroupLayout` | 32,416 | 28,528 |
| `Box.requestLayout` | 10,000 | 4,048 |
| `TupleGroup.requestGroupLayout` | 8,304 | 8,304 |
| `Column.requestLayout` | 4,096 | 4,096 |
| witnesses, `OptionalGroup`, `visit` | 2,224 | 2,224 |
| **per level** | **114,176** | **79,904** |

A level whose `content` is a `Column` of a `Text` and the next level: 12,912 to 8,624 per level. `Frame.renderOutsideDispatch` was 39,488, 72,864 and 88,032 bytes in the controls, looks and menus demos and is 6,240 now.

## What changed

1. **The tail of every recursive frame is an `@inline(never)` helper** (`HP-O`). A frame on the recursion is live under the whole subtree; a debug build gives each local of the whole function a slot in it at entry, however late the local is used. So the code after the recursive call moves to a function whose frame is gone before the next level starts: `Component.finishComponent` (the content and layout copies, the heap box: `sealedComponentLayout`), `Element.requestGroupLayout` (the wrapper: `singleGroupLayout`), `Box.requestLayout` (`finishLayout`), `ModifiedContent.requestLayout` (`finishLayout`), and `Frame.renderOutsideDispatch` (everything after the root's layout, which held every phase's locals: `renderAfterRootLayout`). The recursive frame keeps the one value that crosses the call, the result tuple. No value is boxed and no statement runs a different number of times; the release build inlines or keeps these as before.
2. **`Stepper`'s initialisers do not delegate to each other.** Each public `init` is `self = Self.valued(…)` or `self = Self.make(…)`, static functions whose frames are about half an initialiser's, the body is built in `body(style:label:)` and `control()` in pieces (`upperHalf`, `lowerHalf`, `plus`, `mark`, each `@inline(never)`), and the one memberwise `init` that runs last is a leaf. The chain on the path went from 232,608 to 179,536 bytes. Behaviour is identical: the same style, the same views, the same closures.
3. **The controls demo's left column and its vocabulary section, and the looks demo's lifecycle row, are `Component`s** (`ControlsColumn`, `ControlsPickers`, `ControlsListRow`, `SwiftUIVocabulary`, `LooksLifecycleControls`), the remedy `PE-K` already names ("give each such branch its own `Component`"). They hold bindings, the demos' state stays where it was, and a component is layout-transparent, so no node, rect or label moves. This is demo content, not a framework change; it accounts for most of the controls demo's drop (below), the framework for the rest.

## Numbers (debug, `StackMeter`, macOS arm64, the first frame, 1100 x 700)

| demo | master | layout helpers | + `Stepper` | + demo components (this record) |
|---|---|---|---|---|
| controls | 1,543,872 | 1,498,320 | 1,445,248 | **854,976** |
| looks | 1,177,664 | 1,060,288 | 1,007,216 | **794,480** |
| menus | 893,872 | 697,968 | 697,968 | **697,968** |

`theCensusDemosLayOutBelowOneMebibyte` lists controls and looks and holds both under 900,000 on macOS, every demo under 1 MiB everywhere; `everyReferenceHeldInStateIsClassified` runs the two again (the Windows job is the proof). `aNestingLevelOfLayoutCostsAtMostItsCeilingOfDebugStack` pins the per-level cost: four against eight nested levels, over four; ceilings 88,000 (fat) and 10,000 (thin).

### Release

`StackMeter` is a no-op in release, so the release figure is the high-water mark of the main thread's stack over the whole first frame, found by painting 4 MB below the stack pointer with a pattern and reading how far a window open plus one frame reached (a scratch package over the public API, not committed; resolution one 1,032-byte level; the harness itself, `Text("hi")` in a window, is 62,952):

| demo | master | this branch |
|---|---|---|
| controls | 1,093,920 | 649,128 |
| looks | 748,200 | 748,200 |
| menus | 569,664 (cold), 555,216 (after another demo) | 504,648, 491,232 |
| default demo | 1,071,216 | 1,071,216 |

**Release frames are not a small fraction of debug ones here.** The default demo's first frame reads 1.07 MB in release and is unchanged by this record; the controls demo read 1.09 MB. What fills it in release was not attributed (the sampling points of `StackMeter` are off in release); a 1 MiB Windows main thread is at its edge for these demos in release too. Open item.

### Release time (a scratch benchmark, `setNeedsRedraw` and a tick, three to five interleaved runs each, master against this branch)

| tree | master (us a frame) | this branch |
|---|---|---|
| twelve nested `Component` levels of six buttons (framework only) | 1779, 1734, 1736, 1634, 1655 (mean 1708) | 1771, 1758, 1661, 1703, 1682 (mean 1715) |
| default demo | 1496, 1798, 1839 | 1645, 1647, 1717 |
| controls demo | 1844, 1806, 1810, 1880, 1936 (mean 1855) | 1958, 1881, 1906, 1909, 1999 (mean 1930) |
| looks demo | 4398, 4333, 4328, 4247, 4393 (mean 4340) | 4552, 4438, 4536, 4504, 4594 (mean 4525) |

The framework changes cost nothing measurable. **The controls and looks demos are about 4 percent slower**: their new `Component`s each cost a layout record's heap box and a build of their own, which is what a component is. That is the price of fitting 1 MiB for those two demos and it lands on demo content only; no pin on the default demo or on an app's tree moves (`theDemoDoesTheSameTextWorkAsBefore`, the steady-frame allocation and element-request pins, `G51` and the retained ceilings pass unchanged in the full run).

## Mutations

| mutation | reads |
|---|---|
| `finishComponent`'s tail inline again | fat level 104,336 (ceiling 88,000), thin 10,544 (10,000): `aNestingLevelOfLayoutCostsAtMostItsCeilingOfDebugStack` red |
| `Element.requestGroupLayout`'s wrapper inline again, alone | 83,792 and 8,768: **green**; the ceiling holds the sum of the reductions, not each one |
| `Stepper` as on master | controls 907,984 (over 900,000): `theCensusDemosLayOutBelowOneMebibyte` red on macOS |
| the demos' components inline again | controls 1,445,184 (over 1 MiB and 900,000), looks 1,007,152 (over 900,000): the same test red |

## What is left

- A 10 KB `Stepper` still costs about 180 KB of stack in a debug build to construct, and any element of `S` bytes costs 7 to 8 `S` through `Row { … }`: a container's `init` holds 2 to 3 copies of its content at `-Onone` (probes with a frame-by-frame trace: `self.content = content()` 2 `S`, through a nested `Box` 3 `S`, a `build:` closure instead 4 `S`, `@_transparent` worse). No spelling tried took it under 2 `S` without storing the content in the container itself (`Row`/`Column` would stop wrapping a `Box`), which changes every phase that reads `box`; not done.
- `Element.requestGroupLayout` is still 1.2 `S` (the result tuple of `requestLayout` is held while the wrapper is built); the proposal-layout frames (`VStack.requestProposalLayout` 18 KB, `Picker.requestMenuLayout` 26 KB, `Button.requestChromeLayout` 34 KB in the menus demo) and `Pair`, `OptionalGroup`, `EitherGroup`, `ForEach` and `ScrollView` are not split; menus, at 0.70 MB, did not need it.
- The Windows x86-64 figures are not measured; the macOS ceilings are 10 to 16 percent over their readings.
