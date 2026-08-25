# Milestone 1a — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-25-metalui-m1a-layout.md`, in order. Each says
what was decided, why, and what it costs if wrong.

**14 rulings. Every defect found during execution was in the plan or the spec,
never in an implementation.**

## Pre-flight (from scanning the plan before any code)

| # | Ruling | Cost if wrong |
|---|---|---|
| PF-1 | Resource-directory ordering within Task 3 is not load-bearing; only the end state is. Create fixtures before editing the manifest if SwiftPM objects. | One confusing manifest error. |
| PF-2 | If the `resolveLength` switch expression's mixed `Double`/`Double?` branches fail to type-check, use explicit returns — behaviour matters, not expression form. (It compiled.) | None. |
| PF-3 | Task 7's auto-size fallback (an auto-sized child takes the container's extent) is **not CSS** and stands only because every Task 7 fixture sets explicit dimensions. It must be **deleted, not extended**, by the flex-basis work. | If the grow task builds on it, auto-sized items silently inherit container size forever. |

## Dispatch A — style model and rounding

| # | Ruling | Cost if wrong |
|---|---|---|
| A-4 | The absolute-coordinate contract on `roundLayout` gets **pinned by a test**, not documented. Filed Minor by the reviewer; ruled up because `roundLayout` has no cross-rect state and its whole invariant rests on callers passing absolute coordinates. **Vindicated:** removing the origin term passes both WebKit tests and both hand-written packing tests — only the nested test catches it. The browser corpus is structurally blind to that class. | One extra test. |
| A-5 | `maxSize: .auto` gets documented where resolution consumes it. CSS's initial for `max-width` is `none`, not `auto`, and `Dimension` has no `none` — so `.auto` does double duty as "unconstrained". | A max-size constraint behaving like an auto size; wrong clamping found late. |

## Dispatch B — the WebKit oracle

| # | Ruling | Cost if wrong |
|---|---|---|
| B-1 | Fixture hygiene asserted **at generation time** (`root.x == 0 && root.y == 0`). A fixture omitting `body{margin:0}` otherwise generates a golden at x=8, and the failure surfaces later as what looks like an engine bug. | A future fixture deliberately offsetting its root needs the assertion relaxed. |
| B-2 | An `allFixtures` omission must fail loudly — assert the table's count matches the `*.html` files on disk. Silent under-coverage is worse than a loud failure. | Negligible; test-only. |

## Dispatch C — tree, measure contract, resolution

| # | Ruling | Cost if wrong |
|---|---|---|
| C-1 | Keep multiply-then-widen for percentages — **but my framing of the question was wrong.** I posed it as "strict test vs less exact implementation". The reviewer measured all 20,800 (k%, parent ≤ 4000pt) integer-exact pairs: widen-first misses 61%, multiply-first misses 5.2%. **Neither is exact** — 9% of 300 gives 27.000001907 either way. Kept on the honest ground that every `MetalUICore` scalar is `Float`-backed, so widening first manufactures 16 digits from a 7-digit input. Both errors are ~1e-4pt, 130× below WebKit's 1/64 quantum. | None measurable at any realistic layout dimension. |
| C-2 | The percent test and its comment are a **trap** and get defused. The strict `== 20` passes only by accident of the chosen decimal; the next person to add a 9% fixture hits a mystifying red and "fixes" settled arithmetic. | Negligible — a looser assertion on a property 130× below the comparison quantum. |
| C-3 | No generation counter on `LayoutNodeID` yet. A stale ID after `reset()` traps safely if the new tree is smaller but **silently addresses a different node** if larger. Latent — nothing calls `reset()` mid-flight. | **If M1b resets between building and reading, a stale ID reads the wrong node with no error.** Carried into M1b as a named risk. |

## Dispatch D — the engine

| # | Ruling | Cost if wrong |
|---|---|---|
| D-1 | `gap` and `display: .none` enter the fix round as Important — both deletable with the full 71-test suite green. `gap` required to be **browser**-verified, since gap arithmetic is exactly what an oracle is for. | Negligible. |
| D-2 | The committed goldens were **write-only** and that gets fixed now. `loadGolden` had zero callers; nothing read `Golden/*.json`; hand-editing a golden failed nothing. Engine comparisons now read committed goldens; one live-WebKit staleness guard remains. | If regeneration is forgotten after a fixture edit, the staleness guard catches it — which is the point. |
| D-3 | **Do not** add the in-suite defence against env-gating the staleness guard. The ~8-line guard is text-matching, and no in-suite test can fail when the guard is *deleted* rather than gated. It closes one hole, not the class. | Someone gates or deletes the guard and the oracle silently stops guaranteeing anything. See "Carried to CI" below. |

## Final review

| # | Ruling | Cost if wrong |
|---|---|---|
| F-1 | One fix wave, seven items, no second wave. Items 1 and 2 are **documentation of absence, not implementation** — I explicitly forbade wiring `roundLayout` into `computeLayout`, because where it belongs is the flex-grow task's design decision and guessing here would prejudge it. | The false comment stays false one milestone longer if the wave misreads it. |

## Carried to the first CI setup

**Two guarantees in this project silently lapse under plausible CI configurations, and they are the same failure in two milestones:**

1. **M0's ABI probe *skips* without a Metal device** — CPU/GPU struct agreement is unguarded on a headless runner.
2. **M1a's `committedGoldensMatchTheBrowser` is the only live-WebKit consumer** — gating or deleting it makes the goldens self-confirming.

Both must be **required, non-gateable** jobs. A guarantee that quietly turns itself off is worse than no guarantee, because the green suite now asserts something it has stopped checking.

## Readiness for flex base size — put this in the next brief verbatim

The final review's most valuable output:

- PF-3's fallback is **free to delete** — one `else if case .definite` branch, and mutation proves removing it breaks no test.
- But `resolveNodeSize` serves **both** the root and every item, so the natural-looking move is to add a `flexBasis` check *inside* it alongside the fallback — **exactly the "extend, don't replace" outcome PF-3 forbids.** A separate `flexBaseSize(item:)` entry point forecloses that.
- `layoutChildren` sizes, positions and recurses in **one pass**; CSS §9.7's freeze loop needs collect → resolve → position. That loop must be **split before** any grow code lands, and nothing in the file says so.
- `roundLayout` has **no pipeline slot** and becomes mandatory the moment grow yields `100/7`.
- The measure seam is unwired, yet `flex-basis: auto` on a content-sized item is exactly what calls it.
- The justify-content task should open by making `layoutChildren` return its final cursor and asserting a 3×50 row with `gap: 12` reports **174, not 186** — that pins the trailing-gap fix, which currently has no killing test because nothing reads the cursor.

**Instruction: delete the fallback first, split the loop before writing freeze code, and wire `roundLayout` in the same change** — otherwise the grow work is validated by a comparison that provably cannot tell rounded from raw.

## Known-unproven guards (carried to M1b)

- Neither `EmptyMeasurementError` nor `FixtureHygieneError` has a test; both are implemented but unproven, and either guard could be deleted with the suite green.
- `aspectRatio` is a third live-but-unimplemented `Style` property with no gap docstring, unlike reverse and the box model.
