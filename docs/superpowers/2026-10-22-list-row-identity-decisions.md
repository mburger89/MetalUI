# List row identity by value — decisions (`LH-`)

Round 2 item 8 (user request 2026-10-21; the follow-up `FI-I` named, retires
divergence 255). Spec: [`specs/2026-10-22-list-row-identity-design.md`](specs/2026-10-22-list-row-identity-design.md).
Record: `../record/145-list-row-identity.md`. Branch `feat/list-row-identity` from
`4197f825`. Reserved divergence labels: 745–754 (none taken; `LH-F`).

SwiftUI's side: `docs/probes/swiftui-list-row-identity.swift` (arms L1–L3, run
2026-10-22, output in its header; positive control L3, separating arm L2).
gpui has no analogue (caller-supplied typed ids), so SwiftUI decides.

**Next unused id: `LH-J`.** (Read the last `## LH-` heading, not this line, if
they disagree.)

## LH-A — a `List` row is identified by its id's Hashable value; divergence 255 is retired

**Ruling.** Two rows whose ids print alike and differ in value are two rows with
separate `@State`, `@FocusState`, extent entries and tombstones, in both the
uniform `rowHeight:` path and the variable-height path. Equal values stay one
row. Divergence 255 moves to Retired (label never reused).
**Evidence.** Probe L1 (two rows, two tokens), L2 (each token follows its id
through a reorder), L3 (equal values, one row). Same answer as `ForEach` (`FI-A`).
**Cost if wrong.** A caller who relied on description-equal rows sharing state
never had a documented right to it (the type doc called it an unguarded gap).

## LH-B — the one mechanism is `ElementID(name:key:)`, behind one internal helper

**Ruling.** `List` names a row `ElementID(name: String(describing: id), key: needsKey ? IdentityKey(AnyHashable(id)) : nil)`
with `needsKey = !(ID.self is DescriptionInjectiveID.Type)`, decided **once per
build** (`FI-B`, not per row, not per datum: the data cannot change a row's path
when a twin appears). The three sites share one `package`-free internal helper
`ElementID.forRow(_:keyed:)` in `ElementID.swift`; `ForEach` and the two lazy
sites keep their own spelling unless the implementer finds a byte-identical
refactor (not required, `LH-G`). `FI-K`'s floating-point dedupe is a `ForEach`
rule and does not apply: a `List` never dedupes (a duplicate id in `data` is a
precondition of `Identifiable`, unchanged).
**Alternatives rejected.** A second mechanism (an interning table, a hash in the
name): `FI-B` already rejected both.
**Cost if wrong.** Injective ids mint today's names byte for byte (`LH-C`), so a
wrong helper shows only for custom ids.

## LH-C — injective ids are byte-identical and pay nothing

**Ruling.** For Int family, String, UUID, Bool, Character, Double and Float ids the
row's `ElementID` is `ElementID(String(describing: id))` with `key == nil`: no
`IdentityKey`, no `AnyHashable`, no extra allocation per row, `ElementID` stays 24
bytes and `GlobalElementID` in its 64-byte bucket (`FI-G`, test 2.12 unmoved). A
custom id pays one `AnyHashable` and one `IdentityKey` per **realised** row per
frame, so a warm frame stays O(window) (`LH-E`).
**Cost if wrong.** If the 100k test's work moves for `Int` ids, the pin catches it.

## LH-D — the three sites, and what is already by value

**Ruling.** The sites are (1) the realised row's identity (today
`.id(String(describing:))` on the row `Box`, becomes an assignment of the
`ElementID` to `Box.elementID`, a public settable property, so no public API
moves), (2) the `scrollTo` key note (`DD-K`: `GlobalElementID.child(of: id, at: 0, name:)` must equal site 1's scope or a pending `scrollTo` finds no row),
(3) the accessibility selection request's `byRow` map (`accessibilityRowSelection`).
Already by value, unchanged: selection (`ListSelection` reads `datum.id`, `reader(datum.id)`),
click and lead/anchor logic, `RowExtentIndex` (typed id), the `VL-G` anchor,
`ListOrigin`. The two collisions that exist today are sites 2 and 3 (shared name,
last twin wins) plus shared state at site 1.
**Cost if wrong.** A site left on the plain name makes `scrollTo` or an AX
selection target nothing for a custom id (both red in the pins).

## LH-E — work counted per realised row, separately from `ForEach`'s

**Ruling.** `Frame.listIdentityWork: (rows: Int, keyed: Int)` (internal, beside
`forEachIdentityWork`, which is **not** touched so `FI-B`'s pins stay equal).
`rows` is the realised row count per build, `keyed` the rows that minted an
`IdentityKey`. Pins: `Int` ids `keyed == 0`; custom ids `keyed == rows == window`;
100k rows and 500 rows realise the same window and the same counts. The 100k test
is run before and after and both numbers recorded (counted, never timed).
**Cost if wrong.** A counter that diverges from the realised window hides an O(n) loop.

## LH-F — no new divergence, no public declaration

**Ruling.** The change makes `List` agree with SwiftUI where it disagreed, so no
label is taken (745–754 untouched). `ElementID(name:key:)` and `IdentityKey` stay
internal; plain-import guard G1 (`FI-`) holds and is re-run. The census does not
move. `List`'s type doc paragraph on `String(describing:)` and `ListRows`'s
`.id(String(describing:))` comments are rewritten, and CLAUDE.md's `ForEach`
identity paragraph loses "`List` rows still name by description".

## LH-G — lazy containers are already by value; `ForEach` is not refactored

**Ruling.** `LazyUnits.swift` names its two sites with `ElementID(name:key:)` since
`LZ-`, so a lazy stack's rows were never affected. A test pins that a `List` row,
a `ForEach` element and a lazy unit of the same id name the same `ElementID`
(`aListRowAndAForEachElementNameTheSameID`). Folding the three existing spellings
into the new helper is optional and only if the diff is byte-identical on the
fourteen images and the `ForEach` counters; it is not a deliverable.

## LH-H — TB-AH holds with key-bearing ids

**Ruling.** The tombstone sweep keys on `GlobalElementID`, whose `==`/`cachedHash`
include the component's `ElementID` (`FI-C`), so a keyed row is swept and
resurrected like a plain one: out of window more than two generations loses
`@State` once the table exceeds 256 entries, a bounded excursion keeps it. Pinned
by a keyed twin of `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`.

## LH-I — critic's rejections

**Ruling.** Rejected: a second probe (L1-L3 re-run, same shape); a public spelling (none added); a
renderer or platform change (none); splitting into two lanes (three sites in one file). Accepted: test 7 is a
characterization (labelled), and a keyed row owes an arm in `everyNamingSiteStartsAReturningNameFresh` (ID-R) if
`noteNamed` is reached through `elementID` only.
