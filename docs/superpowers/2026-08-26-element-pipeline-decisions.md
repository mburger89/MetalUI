# Element pipeline — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-25-metalui-element-pipeline.md`, in order. Each
says what was decided, why, and what it costs if wrong.

**Ruling IDs here are prefixed `EP-`.** `PF-`/`C-` belong to m1a, `FS-` to flex
sizing, `AL-` to alignment, `BM-` to the box model, `WR-` to wrapping. A bare
`F-n` is ambiguous across three documents — sweep for stray citations
**case-insensitively**, since a `Ruling F-3` survived two branches' greps for
lowercase `ruling`.

**EP-2 and EP-4 were never assigned.** The numbers are skipped deliberately and
are **not free for reuse**: a future ruling taking one of them would silently
rebind any citation written against the gap. If you need a new number here,
continue from EP-8.

## Structure

| # | Ruling | Cost if wrong |
|---|---|---|
| EP-1 | **The `swiftc -typecheck` machinery lives in one target, `MetalUITestSupport`, under `Tests/`.** Four test files across two test targets need it — `PhaseSeparationTests` (15 guards), `ErasureCompileGuards` (7), `ElementGroupTrapTests` (1) and `UnitSafetyTests` (2) — and SwiftPM gives test targets no way to depend on each other, so the alternatives were a second copy or a target. It is a `.target` rather than a `.testTarget` because only a `.target` can be a dependency; it ships in **no product** and is not one of spec §3.1's targets. What forced the decision is not duplication as such but *which* function is duplicated: `modulesDirectory` carries fix 009768a, which skips `.build/index-build/`. Without it `swift test` was green on a branch and red on the identical merged tree — presenting as a unit-safety regression — purely because an editor had indexed in between with a different toolchain. **A second copy keeps that bug in one place and fixes it in the other, and the next person to hit it debugs the wrong subsystem.** | A fix to a shared, environment-sensitive helper lands in one copy. The failure it causes disguises itself as a regression in whatever the *other* copy's fixture was probing. |
| EP-3 | **Spec §4.6's existential explanation named the wrong mechanism, and the correction changes what a future Swift release would buy.** The paragraph said `LayoutState`/`PrepaintState` "appear in `inout` (invariant) position and cannot be opened", which implies that a Swift permitting `inout` existential opening would make `AnyElement` redundant. It would not. The real rule is SE-0309's: a member is usable on an existential only when its associated types appear in **covariant** (result) position. `LayoutState` and `PrepaintState` appear in **parameter** position, and by-value versus `inout` changes nothing — measured on swiftc 6.3.3, byte-identical diagnostic. Verified by construction both ways: `-> S`, `-> [S]`, `-> S?`, `var prop: S { get }` and `func take(_ f: (S) -> Void)` all compile on an existential; `func byValue(_ s: S)` and `func byInout(_ s: inout S)` both fail identically. `requestLayout` opens precisely because its associated type is in its *return* type. The correction is in the spec, which is the binding authority, and it keeps EP-3. | Someone reads the spec, waits for a language feature that would not help, and leaves a hand-written erasure looking like a workaround for a compiler limitation rather than a consequence of the protocol's shape. |

## Where CSS and SwiftUI disagree

| # | Ruling | Cost if wrong |
|---|---|---|
| EP-5 | **Where CSS and SwiftUI answer a design question differently, take SwiftUI's answer.** CSS is this project's *implementation substrate*: flexbox is the layout algorithm, and a browser is a testable oracle for it, which is the whole value of the 57-fixture corpus. It is not the design authority for anything above the engine — the element API, defaults, spacing, identity, or what a container does when the author says nothing. Those are questions about what a Swift UI framework should feel like, and SwiftUI is the answer the users of this framework already know. **The WebKit corpus stays the oracle for the engine; this ruling binds everything above it.** | The engine and the API drift apart in their idea of what "reasonable" means. A fixture's answer stops predicting a user's answer, and the browser corpus stops being evidence about the framework — it becomes evidence about a layer users never touch. |
| EP-6 | **`Column`/`Row` keep CSS's `stretch` cross-axis default, and no default `gap` is invented.** ***Its mechanism expired on 2026-08-26 — the decision stands, its reason does not; see "EP-6 is unblocked — recorded, not re-decided" in the content-sizing decisions doc, and CLAUDE.md's "Start here". An `auto` cross size measures its subtree now, and the CLAUDE.md row cited below has been deleted. The text is kept as written because a ruling is a record of what was decided and why.*** This is where EP-5 does *not* apply, and the reason is a mechanism rather than a preference. SwiftUI would centre a stack's children on the cross axis. But an `auto` cross size resolves to **0** in this engine (CLAUDE.md's inert table — it is lost in §9.4.8 line measurement), so a centred child with no explicit cross size would measure 0 and **paint nothing at all**. `stretch` is what keeps the demo's sidebar visible. So EP-5's stack half is *blocked on* recursive subtree measurement: it is a prerequisite, not an application. No default gap either, for an unrelated reason — SwiftUI's stack spacing is contextual and platform-derived, not a number, and hardcoding `8` would be a guess wearing SwiftUI's name. `Column(gap:)`/`Row(gap:)` take it explicitly and default to 0. | Every child of a stack with no explicit cross size paints nothing, and the framework's first impression is a blank window. Or a hardcoded gap acquires callers and becomes impossible to change once real spacing rules exist. |
| EP-7 | **Margins stay publicly settable, and an explicit margin outranks any automatic spacing.** SwiftUI has no margin: spacing lives on the container. This engine has margins, they are live (the box-model milestone wired them in), and hiding them would leave an implemented rule unreachable — which is the same defect as an unimplemented one being reachable. `margin(_:)` is public in two overloads, taking `Pixels` and `Edges<Length>`; `.auto` remains unspellable because both take `Length`, not `Dimension`. The second half constrains future work: **if automatic stack spacing lands, an explicit margin must override it, not sum with it.** CSS would sum a `gap` and an adjacent margin; that is the answer to avoid, because it makes a margin's effect depend on which container it happens to be in. | Automatic spacing arrives and silently adds itself to every explicit margin already written. Every existing layout shifts, and the fix is a breaking change to whichever of the two rules loses. |

## Carried into the next milestone

EP-5 creates two prerequisites. Neither is optional if the API is to answer the
way SwiftUI does, and both are engine work rather than API work:

- **§4.3 structural identity.** SwiftUI keys a view's identity on its
  **position in the tree**, with `.id()` as an override. This framework keys on
  `.id()` alone: `GlobalElementID.child(of:_:)` returns `nil` when either end is
  anonymous, so an unnamed container **poisons its whole subtree** — naming a
  leaf under an unnamed parent buys nothing — and two siblings given the same
  name share one state entry with no diagnostic. `id(_:)` is therefore a
  requirement today where SwiftUI makes it an escape hatch. Closing this is what
  lets state be the default rather than an opt-in.
- ~~**An `auto` cross size that measures content** rather than resolving to 0.~~
  **CLOSED by the content-sizing milestone (2026-08-26).** It was EP-6's
  blocker, stated as its own item because it is the larger of the two: recursive
  subtree measurement, not a clamp. It is implemented — `collectItems`'
  `ownCross` calls `measureNode`, WebKit's `120x50` is pinned by
  `flex_nested_auto_cross`, and CLAUDE.md's row describing the hole (a collapsed
  line under wrapping, `align-content` distributing *negative* free space) is
  deleted rather than amended. **So EP-6's stated reason no longer holds**: see
  "EP-6 is unblocked — recorded, not re-decided" in
  `docs/superpowers/2026-08-26-content-sizing-decisions.md`. The ruling's
  *decision* stands until someone re-decides it deliberately; only its mechanism
  expired.

## Carried risk

- **A `canTypecheck` skip turns 25 tests off and leaves the suite green with an
  unchanged total.** This branch's two compile-time exit criteria — phase
  separation and the §4.6 erasure — are both entirely inside that set. Measured:
  forcing `canTypecheck` to `false` skips exactly 25 tests and the summary line
  still reads `Test run with 303 tests … passed`, so taxonomy shape 11's
  count-comparison heuristic does **not** catch it. Recorded in CLAUDE.md's
  "When CI lands" as the third guarantee that must be a required, non-gateable
  job.
- **No border is drawable anywhere in the framework.** `Frame.fill` hard-codes
  `borderColor: .transparent` and `borderWidths: 0`. The blocker is the *width*,
  not the colour: the engine resolves border edges inside `contentBox` and
  discards them rather than storing them on the node, so paint has nothing to
  pair a colour with. Storing the resolved edges on `LayoutTree` is what
  unblocks it.
- **`LayoutTree.reset(generation:)` has no production caller.** The plan
  predicted this branch would reset the tree each frame; `Frame` allocates a
  fresh one instead. Its four guards in `LayoutTreeTests` are kept — they pin
  the contract for whoever does call it — and it has a CLAUDE.md inert row.
- **Nothing in `ElementBuilder` produces an `AnyElement`.** §4.6's escape hatch
  is reachable only by writing `AnyElement(…)` out by hand, and must stay that
  way: the three type-level guards in `ElementLayoutTests` are the only tests in
  the repo that can see boxing.
- **Two guarantees from earlier milestones still lapse** — the ABI probe skips
  without a Metal device, and `committedGoldensMatchTheBrowser` is the only
  live-WebKit consumer.
