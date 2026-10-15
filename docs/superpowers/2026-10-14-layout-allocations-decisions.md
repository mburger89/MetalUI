# Layout and build allocations — decisions

Rulings for item P2 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), from the 2026-10-13
release profile. Prefix `PA-`. Spec: [`specs/2026-10-14-layout-allocations-design.md`](specs/2026-10-14-layout-allocations-design.md).
Record: `../record/119-layout-allocations.md`. Branch `perf/layout-allocations` from `6273e3a4`. Divergence labels
reserved 495–504: none taken. No SwiftUI-facing claim is made (no probe owed, `PA-B`); gpui not consulted (its allocator
is Rust's, not comparable).

**Next unused id: `PA-L`.**

## PA-A — Order by the re-measured share, and claim allocations, not time

**Question.** The profile's list (roundLayout ~806, solveLinearStack ~607, nodeSignature ~381, ForEach ~558, ...) predates
P1 and C14b-2. Which sites still allocate, and what may be claimed?
**Ruling.** The lanes follow the table of spec §1 (measured 2026-10-14 at `6273e3a4`): `roundLayout` 812, `solveLinearStack`
614, `retainedAmbientKey` 392, `nodeSignature` 384, `graft` 340, `StateTable.mark` 151–194 (+ ~290 coroutine frames in
the demo). `ForEach.produceElements` is 223, below the stated 558: P1 removed the rest. A change is claimed as an
**allocation** reduction with a dated count; a time claim needs the A/B of spec §6, because the scratch experiment cut
allocations 7–19 % with no median-ms movement visible under load 25.
**Evidence.** `docs/probes/layout-allocations/` (stack tools, scratch patch); allocs/frame base -> scratch: 7,659 -> 6,598,
5,934 -> 4,847, 19,468 -> 18,158, 2,150 -> 1,733, 1,248 -> 1,049.
**Cost if wrong.** A site that looked large from stacks but is cheap in time is changed for little: bounded by the
reverting rule of `PA-K`.

## PA-B — No public API, no divergence; `roundLayout` stays byte for byte

**Ruling.** `roundLayout(_:)` keeps its public signature and every result; it forwards to an internal scalar
`roundedRect(_:)`. No inventory row, no doc-comment debt, census unmoved.
**Evidence.** The rounding arithmetic is one function body moved, four `rounded()` calls.
**Cost if wrong.** A caller seeing a different rect: pinned by lane-1 test 1 (corpus) and 57 existing tests the doc names.

## PA-C — `reserveCapacity` is exact: reserve geometrically or not at all

**Question.** `graft` calls `reserveCapacity(base + n)` per call and costs 340 allocations per bracket frame.
**Ruling.** Swift's `reserveCapacity` grows to the requested size, not by the amortised factor, so a reserve before each
append batch makes every batch a reallocation and copy. `graft` reserves only when `capacity < need`, to
`max(need, 2 * capacity)`; the same guard for the Int-keyed dictionaries. `removeAll(keepingCapacity: true)` at reset
already keeps the last frame's capacity.
**Evidence.** stacks: 16,804 of 400,000 sampled allocations are `ContiguousArray._createNewBuffer(growForAppend)` directly
under `LayoutTree.graft`.
**Cost if wrong.** Up to 2x capacity retained for a tree that shrinks: a few KB per window; the arrays are per window.

## PA-D — A leaf key's signature is computed at registration, with the same value

**Question.** `nodeSignature` allocates per leaf per run (`AnyHashable.base`, `hash(into:)` box a copy of the
existential).
**Ruling.** `leafKeys` stores a `LeafKey` (key, type id, two hasher words) computed where the key is registered;
`nodeSignature` mixes the same three words in the same order, so **every signature value is unchanged** (the memo,
verify mode and `RK-N` digests keep their meaning); a grafted segment carries them, so a replayed leaf hashes zero times.
**Evidence.** stacks: 13,427 samples in `_AnyHashableBox._canonicalBox` and 6,700 in `AnyHashable.base`, both under
`nodeSignature`.
**Cost if wrong.** A signature differing from the old route would split memo hits: pinned by test 5 (differential) and
`METALUI_VERIFY_LAYOUT_MEMO=1` over the demo. A key mutated between registration and run cannot occur: `AnyHashable`
holds a value.

## PA-E — `StateTable.mark` writes through `index(forKey:)`

**Ruling.** `storage[id]?.isLive = true` becomes a lookup by index and a write through `values`. Kept only if the
allocation count falls (spec M1); behaviour is identical.
**Evidence.** stacks: `swift_coroFrameAlloc` under `Dictionary.subscript.modify` under `mark` is 16 % of demo
allocations (scratch: demo -417 allocations per frame together with `roundedRect`).
**Cost if wrong.** None in behaviour; if the allocation does not fall in the lane's measure the edit is dropped.

## PA-F — `solveLinearStack`: same measurements, same order, fewer containers

**Ruling.** The calls to `measureNative` keep their order and arguments, so the four work counters are equal by
construction and pinned by the differential test; the gap sum keeps the reduce's order (bit-equal floats); a single
priority level skips the `Set`, the sort and the empty `reserved` reduce; flexibilities are an array by member position.
**Evidence.** stacks: `solveLinearStack` 452 allocations per demo frame (21 % of the demo's), 614 per bracket frame.
**Cost if wrong.** A different ordering of equal-flexibility members: `lhs < rhs` tie-break kept and pinned by mutation (a).

## PA-G — `ForEach` keeps its names; only its containers are sized

**Ruling.** `FI-B` and `FI-K` hold byte for byte: the name is still `String(describing:)`, the key still
`IdentityKey(AnyHashable(key))` only for a non-injective id type. `seenIDs`, `nodes` (and `seenNames` for a floating-point
id) are reserved to `data.count`. An Int-name cache is not built.
**Evidence.** 223 allocations per bracket frame remain; `String(describing:)` of an `Int` is small-string (no heap).
**Cost if wrong.** Over-reserving for a `ForEach` of 100k rows: `reserveCapacity` of a `Set<Int>` at that size is the
size the Set reaches anyway.

## PA-H — Only isolation sites that still measure are changed

**Ruling.** P1 removed the sites the 2026-10-13 report named at `Frame.swift` 2373/3224; they read below 0.1 % and are not
touched. The remaining checks total 1.2 % (demo) and 1.3 % (orbit), all in `LegacyLowering` and `RetainedSubtree`
(spec §1); each becomes a `for` loop. Closures passed to stdlib generics from `@MainActor` code elsewhere stay unless a
re-run of `isolation-sites.py` shows >= 0.3 %.
**Evidence.** `docs/probes/layout-allocations/isolation-sites.py` on `rs.sh` samples of demo and bracket-orbit.
**Cost if wrong.** Low: the loops are the same arithmetic.

## PA-I — `retainedAmbientKey` gets a reserve, not a new type

**Ruling.** Eight arrays per key (392 allocations per bracket frame, 5 %) is the largest unfixed site, but its
`environment:` field belongs to C14-c (environment epoch), which edits the same type's producers. This item reserves
capacity inside the scope loop and stops; the struct reshape is deferred to after C14-c merges (spec §7).
**Cost if wrong.** A conflict at merge in a 40-line function: bounded to the loop lines this item touches.

## PA-J — Allocation pins are thread-filtered, differential and Darwin-only; a pin that is not red is a measurement

**Question.** The brief allows malloc_logger counts "only if reliable".
**Ruling.** A test-support `countAllocations` counts only the calling thread's allocations (the main actor runs on a
pool thread under Swift Testing, so a global count would read other threads), with a positive control and a separating
arm. Pins are **differential** (N vs 5N elements: difference 0; distinct capacities <= 12), never absolute numbers, and
each is proven red before the fix **in the test configuration (debug)**. Where debug does not reproduce the release
allocation (coroutine frames, stdlib specialisation), the pin is dropped and the release number is a dated measurement
in the record. Darwin only (`#if canImport(Darwin)`); Linux/Windows run the behavioural pins.
**Cost if wrong.** A flaky pin: the counter ignores other threads; a stdlib change moving a constant cannot move a
difference.

## PA-K — Measure-key hashing is gated on a measured gain

**Ruling.** `LayoutMemo.MeasureKey` gets a cheaper `hash(into:)` (signature words are already well mixed; `==` stays
complete) and `run.cache` is reserved from the previous run; it is **reverted unless the A/B median improves >= 1 %** on
demo or list-fixed with every work counter equal. Hashing in `measureNative` is 7–9 % of a frame (memo lookup 3–4 %,
cache find 2 %, two `setValue`s 3 %), but SipHash's finalisation is a fixed cost, so the achievable share is unknown.
**Cost if wrong.** A weaker hash colliding: the dictionary falls back to `==`, correctness unaffected; verify mode reads
every hit.

## Carried

C14-c's `AmbientKey` reshape; the array-indexed measure cache (P3); the pan raster item (`CoverageRasterizer`);
text placement caches (REPORT E1/E2). Each is named in spec §7 with its reason.
