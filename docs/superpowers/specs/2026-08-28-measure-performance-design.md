# Measure-Path Performance and List Virtualization — Design

**Status:** approved in brainstorming 2026-08-28. Follows absolute positioning
and overlays (merged as `adaab87`).

A human reported the demo window **stutters while being live-resized**, "not
nearly as bad" in release but still present. The investigation that followed
killed the obvious explanation and found a different one, and this document is
built on those measurements rather than on the report.

---

## 1. What was measured, and what it ruled out

Measured 2026-08-28 at `8b72a06` with a throwaway harness that copied
`demoContent()` verbatim (103 nodes, 44 `Text`), driving `Frame` directly. GPU
submission and AppKit are excluded. **Absolute times are machine-specific; the
ratios transfer.**

**The resize is not the problem.** A cold width sweep costs **1.038x** what
sitting still costs:

| run | mean ms (release) |
|---|---|
| steady @920, warm | **4.970** |
| sweep 0.50pt/frame, cold | 5.159 |
| sweep 0.50pt/frame, pre-warmed | 4.952 |

**The `ShapingCache` hypothesis is dead**, and it was killed rather than
argued: a sweep misses **3.9 times per frame out of 1308 lookups — 0.3%** — and
pre-warming the sweep's exact widths moved the frame by **4.0%**. The premise
("every frame has a new width, so every `Text` misses") holds for exactly
**one** of the 44 `Text`s, because the 40 rows are pinned to a literal
`.width(Pixels(420))` and never re-wrap on a horizontal resize.

**The cost is flat and paid on every frame.** Idle, the display link pauses; a
drag is simply the only time the app draws continuously. Debug is a flat
**3.24x** constant factor (16.108 ms), which alone exceeds a 60 Hz frame — that
is the whole of "much worse in debug, still there in release."

Where a release frame goes:

| phase | ms | share |
|---|---|---|
| **`computeLayout`** | **3.464** | **69.7%** |
| **paint (glyph emit)** | **1.114** | **22.4%** |
| `requestLayout` walk | 0.286 | 5.8% |
| everything else | 0.106 | 2.1% |

The same 103-node tree with every `Text` replaced by a childless `Box` costs
**0.221 ms of engine time against 3.464 — 15.7x**. The measure functions are
~93% of the engine.

---

## 2. The two real costs

### 2.1 A min-content probe is 52x a max-content probe

| operation (warm, release) | cost |
|---|---|
| `textMeasure(.minContent)` on a row | **30,660 ns** |
| `textMeasure(.maxContent)` on a row | 555 ns |
| `Shaper.unbreakableRuns(of:)` on a row | **27,256 ns** |
| `ShapingCache.shaped()` hit | 604 ns |

`Text.requestLayout`'s `.minContent` branch (`Text.swift:74-90`) tokenizes the
string into unbreakable runs and then shapes **each run separately** through the
cache. Neither half is memoized as a whole:

- `Shaper.unbreakableRuns` has **no cache at any level** — 89 calls/frame at
  27.3 us = **2.43 ms, 49% of the release frame**, and 70% of engine time.
- The per-run loop is where **1308 shaping-cache lookups per frame** come from —
  29.7 per `Text`. At 604 ns each that is a further **~0.79 ms**.

Together: **~3.2 ms of a 4.97 ms frame.**

**The existing comment at `Text.swift:76-79` is why this survived.** It reasons
correctly that the *runs* are cache-shared between frames and "a second frame
adds no misses" — true of the shaping, and it does not notice that
`unbreakableRuns` itself is recomputed in full every time. A true sentence about
one half read as a claim about both.

`unbreakableRuns` is also nearly build-mode independent (27.3 us release vs 31.7
us debug) because it is CoreFoundation, not Swift. It is a **fixed** tax debug
cannot amortise.

### 2.2 Cost is linear in TOTAL rows, not visible rows

Rows are 28pt in a ~370pt viewport, so ~13 are ever on screen. Release, median
per frame:

| rows | total | engine | `unbreakableRuns`/frame |
|---|---|---|---|
| 10 | 1.054 ms | 0.742 | 20 |
| **40** | **4.040 ms** | 2.839 | **80** |
| 160 | **16.114 ms** | 11.270 | 320 |

Dead linear at **~0.101 ms per row per frame**, with exactly 2 tokenizer calls
per row per frame. A 160-row list blows the whole 60 Hz budget in release with
nothing else on screen.

---

## 3. Scope

**Target: 8.33 ms (120 Hz) for the demo tree in release**, with headroom for GPU
submission and AppKit, neither of which was measured.

**In:**

1. **A committed performance harness that asserts counts, not times** (§4).
2. **Memoize the min-content width** per `(string, font)` (§5).
3. **Bound both caches** (§6).
4. **`List` with windowing** (§7).
5. **Re-measure the probe count and decide** whether reducing it is still worth
   it (§8) — explicitly contingent, not committed.

**Out, deliberately:**

- **Variable row heights in `List`.** Windowing without laying rows out requires
  a uniform declared height; variable heights need a prefix-sum index or
  estimate-and-correct, which is its own milestone.
- **Per-row element state surviving a scroll out of the window** (§7.4). Needs
  the tombstone machinery design spec §4.3 already names as absent.
- **Moving layout off the main actor.** The measure closure's
  `MainActor.assumeIsolated` would have to be rewritten first (CLAUDE.md records
  this as a live release trap), and nothing here needs it.
- **Paint-side optimisation.** Paint is 22.4% and windowing removes most of it
  for lists; revisit only if measurement after §5 and §7 says so.

---

## 4. The harness, and why it comes first

**It asserts counts and complexity, never wall-clock.** Every defect above is a
count — 89 tokenizer calls, 1308 lookups, 2 calls per row per frame, cost linear
in total rows. Counts fail identically on a loaded CI box; committed timing
baselines are machine-specific and rot, which CLAUDE.md already warns about for
its own figures.

Three assertions:

1. **`unbreakableRuns` runs at most once per distinct string per frame**, and
   zero times on a warm frame. Today: 89 calls for ~13 distinct strings.
2. **A `List`'s work is identical for 160 rows and 40 rows** — nodes created,
   tokenizer calls and glyphs emitted **equal**, not merely close, since both
   show ~13 rows. With a uniform row height the window is computed by division,
   so `List` never iterates its data.
3. **Cache entry count stays under a declared cap** across a width sweep. Today
   `ShapingCache.storage` goes 276 -> 739 over 120 frames with no bound at all.

**Instrumentation ships.** `ShapingCache` already carries internal
`hits`/`misses` counters that only tests read (`ShapingCache.swift:70-71`) —
that is the precedent, and the new counters follow it: internal, always on, one
`Int` increment.

**The harness lands against today's code, where all three assertions FAIL.**
That is the point. A performance test that passes on arrival has proven nothing,
and this repo's own practices doc catalogues that shape. Each assertion must
also be reddened by a mutation once green — remove the memo, remove the
windowing, remove the bound. **A mutation that reddens nothing is a broken
instrument or it is the finding.**

---

## 5. Memoize the min-content width

**Key on `(string, font)`, storing the resulting width** — not on the runs.

Caching `unbreakableRuns` alone removes the 2.43 ms tokenizer cost and leaves
the ~0.79 ms of per-run lookups behind. Caching the min-content *result*
collapses both into one dictionary hit: the tokenizer walk and the whole loop
disappear together.

Expected: tokenizer calls 89 -> 0 per warm frame, shaping lookups 1308 -> ~88
(44 `Text` x 2 probes x 1 lookup). **Predicted frame 4.97 -> ~1.8 ms; this is a
prediction and the plan must measure it, not assume it.**

**Correctness argument, stated because a memo that returns a stale width is a
silent wrong answer.** `unbreakableRuns(of:)` is a pure function of the string —
it takes no locale and no width (`UnbreakableRuns.swift:107`). The min-content
width additionally depends only on the resolved font, which `FontKey` already
identifies including variation coordinates and matrix. Width is **not** part of
the key and must not be: min-content is by definition width-independent, which
is precisely why §4.5 can use it as a floor.

**`FontKey` is the key, never a family or PostScript name** (spec §6.1 and
§3.2): requesting `"SFMono-Regular"` by name on the machine this was measured on
returns a font whose PostScript name is `Helvetica`.

---

## 6. Bound both caches

`ShapingCache.storage` is unbounded, `Window` owns one for the process lifetime
(`Window.swift:53`), and there is no eviction path — `evict`, `removeAll`,
`limit` and `capacity` all find nothing in that file. A 10-second drag banks
~2,300 entries.

**This is hygiene, not the stutter, and the measurement says so plainly**: a
733-entry cache measured marginally *faster* than a 276-entry one (4.932 vs
4.970 ms, inside noise). It is in scope because §5 adds a second cache beside
it, and shipping the same unbounded defect twice is worse than the first one.

**A bound needs a policy and the policy needs a reason.** The atlas's own
`evictUnusedSince(_:)` is the cautionary precedent: it has zero callers, and
CLAUDE.md records that calling it would make things *worse*, because the shelf
packer cannot reclaim the pixels it frees. A cache bound with no reclaim story
is that bug again. Generation-sweep (mark on use, drop what a frame did not
touch) fits the frame brackets `Frame.render` already has.

---

## 7. `List` and windowing

### 7.1 Spelling

```swift
ScrollView {
    List(items, rowHeight: Pixels(28)) { item in
        Text(item.label)
    }
}
```

`ScrollView { … }` is unchanged and still lays out arbitrary content in full.
Virtualization needs to know its children are a uniform sequence, which a
builder block cannot promise, so it gets its own element.

### 7.2 Uniform row height is required, and it is what makes this O(visible)

Windowing must decide which rows intersect the viewport **without laying any
out**. A declared uniform height gives an exact window by division. `List`
reports a content height of `count x rowHeight`, so the scrollbar, the offset
clamp and overscroll stay correct while only visible rows are built. Overscan of
one or two rows each side, so a partially scrolled edge never shows a gap.

### 7.3 Identity comes from the data, and that is forced

Rows must be keyed by data identity (`Identifiable`, or an explicit id key
path). This is not a preference: identity in this framework is structural, and
`.positional(Int)` components are assigned by the cursor walking the built
children. A windowed row that scrolls out and back would land on a different
position and **adopt a neighbour's state** — the vanishing-`if` hazard CLAUDE.md
already documents, made routine.

### 7.4 The scroll offset is needed in `requestLayout`, and today it is resolved in prepaint

This is the risky part of the milestone and it is a real reordering.

The tree is rebuilt every frame, so `List` must decide which rows to *build*
before the phase that currently computes where anything is.

**Chosen: `ScrollView` publishes its resolved offset and viewport onto the pass
during `requestLayout`**, as an ambient value in the shape of the existing clip
stack, and `List` reads it. Same-frame and correct.

Rejected, with reasons:

- **Use last frame's offset.** Trivial, and wrong exactly when it shows: fast
  scrolling leaves blank bands at the leading edge.
- **Make `List` the scroller.** Sidesteps the reordering, but the chosen
  spelling is `ScrollView { List(…) }` and two scrolling elements is a worse
  API than one ambient value.

**What this touches is the subsystem with the worst track record in this repo.**
The clipping milestone shipped two intermittent scroll defects that only a human
found, one of them an offset clamped on read and unbounded on write. Ruling
CL-C's `contentStyle.flexShrink = 0` and `resolvedOffset`'s clamp-and-write-back
are both live and both easy to disturb. The plan pins current routing behaviour
**before** touching it.

### 7.5 What a windowed row loses

An unbuilt row registers no identity that frame, so the state sweep reaps it.
Per-row element state does not survive scrolling out of the window. `List` rows
keep state in the data for this milestone, and the limitation is **recorded**
rather than worked around; surviving it needs the tombstones design spec §4.3
names as a prerequisite for exit transitions.

---

## 8. The probe count — contingent, not committed

Each `Text` takes **2.02 min-content probes per frame** (89 calls / 44 `Text`).
`LayoutContext` has a memo cache with a test proving it is consulted, so the
open question is why the second probe
misses it — most likely a different `available` key.

**Cite that test by file, never by bare name.** `theCacheIsActuallyConsulted`
exists **twice** — `Tests/MetalUILayoutTests/MeasureCacheTests.swift` is the
engine memo meant here, and `Tests/MetalUITextTests/ShapingCacheTests.swift` is
the shaping cache, a different mechanism. A bare citation resolves to the wrong
one half the time, which is the hazard the ruling-ID prefixes exist for.

**After §5 a min-content probe drops from 30.7 us to roughly one 604 ns
dictionary hit, so this fix's value falls by ~98%.** It is therefore sequenced
after a re-measurement and may be dropped entirely. Reducing it means changing
what the engine measures and when, and 81 goldens sit downstream of that path —
a bad trade for a saving that may already be gone.

---

## 9. Exit criteria

1. `swift package clean`, warning-free build **including `MetalUIDemo`**, full
   `swift test` **summary line** read — never the exit status.
2. **No golden moved.** 81 today. This milestone touches the measure path, so a
   moved golden means something reached the engine that should not have — stop
   and report, do not regenerate.
3. The harness's three count assertions pass, and each is reddened by a named
   mutation.
4. The demo tree's release frame is **under 8.33 ms**, measured and recorded
   with the machine named.
5. A 160-row `List` costs what a 40-row `List` costs, by count.
6. **A human runs the demo and reports whether the resize stutter is gone**, in
   both debug and release. Performance is felt; the same argument that made
   z-order a look applies here, and no assertion in this repo can make it.

---

## 10. Divergences and risks recorded up front

1. **`List` rows lose element state when scrolled out of the window** (§7.5).
   Recorded, not fixed.
2. **`List` requires a uniform declared row height** (§7.2). A caller with
   variable-height rows has no spelling and must use `ScrollView` directly,
   paying the full O(n).
3. **The 8.33 ms target excludes GPU submission and AppKit**, neither measured.
   Hitting it in the harness does not prove 120 Hz on a real display, and the
   exit criterion's human check is what covers the gap.

---

## 11. Decomposition

Roughly, for the plan to refine.

1. Counters and the harness, asserting counts against today's code — **all
   three assertions failing on arrival**.
2. Memoize the min-content width; assertion 1 goes green. Re-measure and record.
3. Decide §8 on that measurement; record the ruling either way.
4. `List` with uniform row height and data identity, not yet windowed.
5. `ScrollView` publishes offset and viewport in `requestLayout`; pin existing
   scroll routing first.
6. Windowing plus overscan; assertion 2 goes green.
7. Bound both caches with a generation sweep; assertion 3 goes green.
8. Demo uses `List`, CLAUDE.md, decisions doc (`MP-` prefixed, lettered), human
   verification.
