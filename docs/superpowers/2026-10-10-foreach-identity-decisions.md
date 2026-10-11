# ForEach identity — decisions (`FI-`)

Item C20 of the gpui-gap list (MetalCreator gap M7-a). Spec:
`docs/superpowers/specs/2026-10-10-foreach-identity-design.md`. Record:
`docs/record/95-foreach-identity.md`. Branch `fix/foreach-identity` from
`280d706`. Reserved divergence labels: 255–264.

**Next unused id: `FI-L`.** (Read the last `## FI-` heading, not this line, if
they disagree.)

## FI-A — a `ForEach` element is identified by its id's Hashable value; divergence 79 is retired for `ForEach`

**Ruling.** Two ids equal in description and unequal in value produce two
elements with separate `@State`; equal values stay one (F7). Divergence 79
(`DD-L`) is **retired** (label never reused; record ref §95); the `List`
residue is a new divergence 255 (FI-I).
**Evidence.** `docs/probes/swiftui-foreach-hashable-identity.swift` H1–H3
(output in its header) and S6/S7 of `swiftui-scrollviewreader-scope.swift`;
gpui has no analogue (caller-supplied typed ids), so SwiftUI decides.
**Cost if wrong.** A caller who relied on the second twin vanishing never
existed (it was a documented loss); a caller whose ids print alike now gets
both elements, as SwiftUI.

## FI-B — keyed always for non-injective id types, never only for a colliding class

**Ruling.** `needsKey = !(ID.self is DescriptionInjectiveID.Type)`; every
element of a custom-id `ForEach` carries its value.
**Reasoning.** Keying only the elements whose description collides this frame
changes the first twin's path when a second appears: its `@State` resets,
exactly the identity instability `ID-C` forbids. A static per-type decision
cannot depend on the data.
**Alternatives rejected.** (1) A per-window interning table AnyHashable →
integer: window-lifetime growth and a pruning rule for no benefit. (2) Encoding
a hash into the name string: collisions again, only rarer. (3) Warning only:
feasibility is shown; the fallback was for infeasibility.
**Cost if wrong.** Custom-id `ForEach`es pay one `AnyHashable` per element per
frame (counted, spec §3.6); if a measurement showed that too dear the marker
list grows (a conformance, additive).

## FI-C — `GlobalElementID.==` and `cachedHash` are untouched

**Ruling.** The discriminator lives in `ElementID`, so `PathComponent`'s
synthesized equality and hash carry it and the chain walk plus parent-in-hash
condition stay exactly as they are. Test 2.8 pins unequal-by-key paths
without touching the walk.
**Cost if wrong.** None to the walk; a synthesized-`==` regression is mutation M8.

## FI-D — `ID-R` / `noteNamed` and the naming-site guard

**Ruling.** The `ForEach` site already calls `noteNamed` on its scope; the
keyed scope is the same call. `everyNamingSiteStartsAReturningNameFresh` gains
one twin arm; no new site mints a name, so no new `noteNamed`. The seven
retention slots are unmoved (the key is not a slot).

## FI-E — `.id(_:)` and `ScrollViewReader` keys unchanged

**Ruling.** `.id` stays `String`-taking (`ID-G`); `scrollTo` keys stay
`AnyHashable` by value (`DD-K`); the keyed scope's typed key is the same
`AnyHashable(id)` already noted. A `Hashable` `.id` overload is additive and
not asked for.

## FI-F — no warning for equal-value duplicates

**Ruling.** Unchanged silence (F7). SwiftUI warns on equal ids; the request's
fallback warning was for the unequal-same-description case, which is gone.

## FI-G — `ElementID` grows 16 → 24 bytes; measured, not assumed

**Ruling.** An internal optional `IdentityKey` (a final class, so exactly one reference; see FI-J) is the carrier.
The lane records `MemoryLayout<ElementID>`/`<PathComponent>` and the
`GlobalElementID` instance size (`malloc_size`) in the record; a bucket change
is a finding to report, not a reason to change the design silently.
**Cost if wrong.** A larger path node on every frame's identity chain; the
alternative (a side table) is FI-B's rejected (1).

## FI-H — no human check

**Ruling.** No look and no input path changes; the proof is the 0-px
comparison and the tests of the spec. Identity reordering is covered by 2.2.

## FI-I — `List` rows are deferred; divergence 255

**Ruling.** `List` keeps `ElementID(String(describing: datum.id))` at its
three sites; the silent aliasing documented in its type doc becomes divergence
**255** (SwiftUI keeps the rows apart; pinned by 2.10). The fix reuses
`ElementID(name:key:)` unchanged and owns the 100k-row work-count re-take, so it
is its own item (owner: a follow-up "List row identity by value"), kept out of
this branch because `List` windowing, TB-AH and `RowExtentIndex` are on the
must-not-move list.
**Cost if wrong.** MetalCreator's `List` users with description-colliding ids
still alias (unchanged from today); its `ForEach` canvas is fixed.

## FI-J — `IdentityKey` is a final class, not a struct around `AnyHashable`

**Ruling.** A struct holding an `AnyHashable` can be wider than a word, which
would make FI-G's 16 → 24 claim false by construction. A final class forwards
`==`/`hash` to its `AnyHashable` and short-circuits on identity.
**Rejected.** Struct carrier (size unmeasured, unbounded by design).

## FI-K — floating-point ids keep the name dedupe

**Ruling.** `Double`/`Float` stay on the no-key fast path (description is
injective on non-NaN values), but a NaN id is unequal to itself, so `Set<ID>`
never dedupes it and, with the name set gone, every NaN would mint the same
path. A `BinaryFloatingPoint` id type keeps the `Set<String>` insert (test 2.11,
mutation M10); other fast-path types pay nothing.
**Rejected.** Keying floats (a keyed NaN is unequal to its own path: state lost
every frame).

## FI-L-reserved — critic review rejections

The critic re-ran probe arms H1-H3 byte-for-shape (tokens random, shape equal)
and rejected, with reason: moving the `List` fix into this branch (FI-I stands:
must-not-move list); a per-window interning table (FI-B).
