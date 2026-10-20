# Retained geometry - decisions

Rulings for item C14-f. Spec: [`specs/2026-10-20-retained-geometry-design.md`](specs/2026-10-20-retained-geometry-design.md). Record:
`../record/128-retained-geometry.md` (Record phase). Branch `perf/retained-geometry` from `99b21a1c`. Reserved divergence labels 575-584:
none taken.

Prefix **`RG-`**, lettered. **Next unused: `RG-K`.** (Moves in the commit that appends a ruling.)

**Carried.** `RK-E` (geometry note taints, now replaced), `KF-J` (delivery semantics, unchanged), `FS-G`, `FS-P`, `FS-T` (record 126),
`SB-AD`, `RK-S`, `RW-` (record 121), C14-e parts (c) and (f).

## RG-A - A geometry note is a ledger entry, replayed by re-noting

**Ruling.** `Frame.noteGeometry` records `(watch, key, owner, value, global)` in the `PrepaintLog` and no longer taints; the ledger replays
each record through `LifecycleStore.noteGeometry` in recorded order when its prepaint key is equal. **Evidence.** `closeGeometry` drops an
un-noted key silently, so a skipped note is a G7 re-report of `initial`, a visible change: replay must re-note, not skip. The proxy is a
function of the key's rects, offset, effect and (refused-when-open) named spaces, so an equal key means an equal value.
**Alternatives rejected.** (1) Keep the taint and make the observer's occurrence a retention boundary: loses the whole occurrence, the
measured 222 vs 199 requests. (2) Re-evaluate the transform at replay: needless when the key is equal and a user closure runs for nothing.
**Cost if wrong.** A transform that captures state the key does not hold replays a stale value; the contract is `.equatable()`'s already
(value-function), and test 3 compares to a fresh window over a script.

## RG-B - The delivery semantics are untouched; the pin is differential

**Ruling.** The action still runs in the lifecycle drain after the build, only when the value differs from the last delivered; the proof
is test 3 (retention on vs `testingRetainedSubtrees = false` over resize, scroll, shift) and `GeometryChangeTests` unedited. No SwiftUI
probe: no observable behaviour moves. **Cost if wrong.** A delivery-order change shows as a red differential; nothing public.

## RG-C - A translated replay holding a geometry note refuses by name

**Ruling.** `movedPrepaintLedger` returns `.refused("geometryTranslated")` for a ledger with a geometry record. **Reasoning.** Today it is
ineligible every frame (taint), so a refusal is no regression, and a translated value needs the user closure re-run over a shifted proxy
(size equal, global frame moved, effect composed): correct only with the transform closure called at replay, which this item does not need
for the measured orbit case (steady, untranslated). **Cost if wrong.** A scrolling list of observers keeps building (the cost of today);
carried with the figure that would justify it.

## RG-D - `onModifierKeysChanged` stays a taint

**Ruling.** Out of scope: its value is window-wide (`Window.currentModifiers`), not subtree-derived, so a ledger value would be stale by
construction; it needs its own design. **Cost if wrong.** none new.

## RG-E - Placement translation is built only if measured dominant

**Ruling.** Commit 1 of lane 2 re-takes the FS shift fixture's counters. If root misses and signature nodes are not the dominant remaining
cost of F2/F3 the item records "not justified" with the figures and builds nothing. If built: an origin-free second dictionary of
origin-relative rects, hit only when every coordinate is an exact sixteenth (as `RK-S`), verify-switch checked; the existing exact key
decides otherwise. **Reasoning.** `FS-G` named this the kernel's neighbour: smallest edit, additive, no change to existing lookups.
**Alternatives rejected.** Dropping the origin from the existing key: breaks float exactness for sub-sixteenth origins (value identity).
**Cost if wrong.** Placement of shifted rows stays whole; measure-memoised already.

## RG-F - `hitboxClipped` gets two pins, not a rewrite

**Ruling.** Pin both sides of the guard with a legacy inner `clipped(to:offsetBy:)`: inside-both moves, touching refuses. The guard text is
unchanged unless a pin proves it wrong. **Cost if wrong.** A refusal that should move costs a prepaint, never pixels.

## RG-G - A shift under a moved render effect: pin the refusal

**Ruling.** Measure the shifted frame under `.offset`/`.scaleEffect` above the occurrence; pin the current refusal by name unless replaying
is a few lines (`RK-G` says a hitbox clip that depended on the effect refuses). **Cost if wrong.** A moving effect keeps building.

## RG-H - Atlas dirty regions: a capped per-shelf list, the union kept

**Ruling.** `dirtyRects` extends the last rect for the same-shelf x-adjacent slot, else appends; cap 8 then one bounding rect;
`dirtyRect` is the computed union so every reader and the public inventory keep compiling. Uploads are per rect (Metal `replace` per
rect; SDL one packed transfer, one copy per rect); the headless counter is the sum of areas. **Evidence.** MetalCreator fillet-drag step
51: 350 texels inserted, 26,468 uploaded; SDL uploaded the whole atlas on any dirt. **Reasoning.** Shelves are the packer's own rows, so
a shelf-merge is exact with no extra scan; gaps merged by threshold are deferred (a per-rect call has a fixed cost; measure before a
heuristic). **Cost if wrong.** A glyph missing from the upload shows blank: test 17 compares every texel to the atlas, and a new or resized
texture still uploads whole.

## RG-I - Critic pass: collapse is sticky; the replayed action closure is the first build's

**Ruling.** (1) After the ninth rect collapses `dirtyRects`, further `markDirty` calls union into that one rect until `clearDirtyRect()`
(never re-grow to eight after a collapse within a frame): keeps the list a sound superset. (2) A replayed geometry note re-notes the
**recorded** record, including its action closure from the build that produced it; this is the `.equatable()` contract already carried by
every replayed handler (a skipped getter keeps its closures), not a new hazard, and test 3 compares deliveries to a fresh window.
(3) Test 5 uses a pure shift, not a scroll: a scroll changes the ambient offset and misses before translation is considered.
**Rejected:** a SwiftUI probe (no observable behaviour moves, `RG-B`); making `dirtyRects` `package` (read by `Backends/SDL`, a separate package).

## RG-J - A ledger holding a geometry note is never grafted

**Ruling.** `Frame.graftRecord(for:id:key:)` returns `nil` (naming `geometryGraft` in `graftRefusals`) when the occurrence's prepaint ledger
holds a geometry note. **Evidence.** Measured in lane 1's test 5: a graft decides before layout, so a shifted grafted occurrence meets
`RG-C`'s `geometryTranslated` refusal after the layout it skipped, the prepaint cannot run on a graft, and the window **redoes the frame**
(`retainedRedos == 1`, the refusal's counter lost with the abandoned build) and backs replay off for eight builds. Before this item the
occurrence was prepaint-ineligible, hence never grafted, so a shift cost one ordinary build; a graft would make it cost two plus a
backoff. **Reasoning.** The win this item names is prepaint (and paint) replay of an observer; the build recursion of an observed
occurrence keeps running, as the 199 requests of an unobserved retained frame do not claim otherwise. **Alternatives rejected.** Letting
the graft stand and eating the redo (a scrolling list of observers builds every frame twice); teaching the graft to foresee a translation
(layout is not known at the graft decision, `RK-C`). **Cost if wrong.** Element requests of an observed occurrence stay whole; carried with
`RG-C` (re-evaluating the transform under translation would lift both).
