# The box model — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-25-metalui-box-model.md`, in order. Each says what
was decided, why, and what it costs if wrong.

**5 rulings — and the milestone where the streak broke.** Four consecutive
milestones ended with "every defect found was in a plan, a test, a fixture or a
comment, never in an implementation." This one shipped **three real correctness
bugs**, all caught before merge, none visible to the test suite at the time. See
"Why the streak broke" below; it is the most useful thing in this document.

**Ruling IDs here are prefixed `BM-`.** `PF-`/`C-` belong to m1a, `FS-` to flex
sizing, `AL-` to alignment. A bare `F-n` is ambiguous across three documents —
sweep for citations **case-insensitively**, since a `Ruling F-3` survived two
branches' greps for lowercase `ruling`.

## Pre-flight

| # | Ruling | Cost if wrong |
|---|---|---|
| BM-1 | **`margin` stays `Edges<Dimension>`, diverging from spec §5.2's `Edges<Length>`.** Margin is the only one of the three that can be `auto`, and `margin: auto` is how "push this to the right" is written in CSS. A `Length`-typed margin makes it unrepresentable, so implementing it later would be a breaking model change rather than one new branch. It ships inert, with a CLAUDE.md row and the "not implemented" note sitting on the `?? 0` operator where the change will actually be made. | `.auto` is expressible and does nothing — a documented row rather than a silent gap. |
| BM-2 | **The fixture note's reasoning was wrong; correct it before it misleads.** The plan said `#root`'s padding rule must follow the `*` reset "so the reset does not zero it". Order is irrelevant: `#root` is an id selector (1,0,0) against `*` at (0,0,0). Left standing, someone tidying the stylesheet would think they had broken it. | None to the code. An hour of someone's confusion. |
| BM-3 | **Name the content box's consumer whose name does not say "container".** `collectItems` binds `parent = OptionalSizeD(width: containerSize.width, …)` — what a child's **percentage size** resolves against, and CSS resolves that against the parent's *content* box. The plan's "pass `box.size` where `containerSize` went" covered it, but silently, and no fixture reached it. | Percentage children resolve against the border box — off by exactly the padding, only in padded containers. |

## During execution

| # | Ruling | Cost if wrong |
|---|---|---|
| BM-4 | **Record the over-constrained-box divergence; do not implement it.** When padding + border exceeds the specified width, WebKit *grows the border box* (measured: 120×140 where we give 100×80) — CSS agrees, `box-sizing: border-box` defines used width as `max(specified, padding + border)`. Implementing it belongs in sizing, not `contentBox`, and it moves a node's *stored* size, which the freeze loop and every ancestor consume. Too much reach mid-plan for a style that is already a mistake. Pinned by a test naming WebKit's numbers, plus a third entry in CLAUDE.md's known-divergences section. | A container whose padding exceeds its width lays out smaller than CSS says. Documented; reachable only by a style that is already wrong. |
| BM-5 | **Task 3 absorbs the composition gaps Task 2 exposed.** Task 2's two bugs both lived in two-feature compositions present in the engine and absent from the corpus. A reviewer named two more — stretch + `min-height` + margins, and reverse + stretch composed — verified both against WebKit by hand, and found the engine correct. *Untested-correct* is exactly the state the two bugs were in before someone probed them, so both got fixtures. | Two more compositions stay unguarded until something breaks them. |

## Why the streak broke

Three real bugs, all found before merge, none visible to the suite at the time:

| Bug | What CSS says | What we did | Found by |
|---|---|---|---|
| Reverse containers put `margin-left` on the item's physical right | `marginMain` is physical; the reversed branch added its `leading` to a *flex-relative* cursor | WebKit `a.x=320`; engine `340` | reviewer probing reverse × margins |
| A stretched item's cross size ignored cross margins | CSS stretches the **margin box** | WebKit `50×65`; engine `50×100`, overflowing | reviewer probing stretch × margins |
| Percentage padding resolved against the box's **own** width | it resolves against the **containing block's** width | WebKit `27`; engine `20` | implementer, while writing the nesting fixture |

The third is the instructive one: **the plan's own code block encoded it.** Tasks 1
and 2 both shipped it faithfully, and it survived two reviews, because every fixture
until then had padding on the *root*, where the box's own width and its containing
block's width are close enough to look right.

The honest generalisation is not that the earlier streak was luck. The first four
milestones were each **one feature deep**, where a plan defect is the likeliest
error and an implementation has little room to be subtly wrong. This is the first
task whose feature multiplies against three already-shipped ones — reverse,
stretch, and `justify-content`. **Composition is where implementations start being
able to be wrong**, and a corpus grown one feature at a time covers each feature
and none of their pairs.

So the rule this milestone adds:

> **When a plan adds a feature that composes with an existing one, the fixture list
> must name the composition, not just the feature.** "Untested but correct by
> construction" is the state every one of these bugs was in the day before it was
> found.

## What the corpus kept failing to see

Continuing the tables in the flex-sizing and alignment decisions docs:

| Blindness | What it hid |
|---|---|
| Every padded fixture put the padding on the **root** | That percentage padding used the wrong basis — on a root, own-width and containing-block-width are indistinguishable |
| No fixture was strongly non-square with percentage padding | That vertical percentage padding resolves against **width**; a square makes both bases agree. This mutation stayed green through two entire tasks |
| No fixture combined reverse with margins | `margin-left` landing on the physical right |
| Both margin fixtures gave children explicit heights | That stretch ignored cross margins — stretch never engaged |
| No fixture had a percentage-sized child inside a padded container | Whether children resolve percentages against the content box (BM-3) |
| No fixture combined grow + `space-between` + margins | Whether the two margin paths double-count. They do not — but nothing proved it until a reviewer built the case by hand |
| No test resolved a **percentage margin** | Whether margins use the containing block's width, like padding and border. Asserted in two doc comments, verified against WebKit five ways by a reviewer, and pinned by nothing — mutating the basis to the container's *height* left all 171 tests green. Closed at branch end by `percentageMarginsResolveAgainstTheContainingBlockWidth`, which reddens with 10-vs-40 on both axes |

## Carried risk

- **The last green mutation on this branch was closed, not documented.** A
  reviewer found percentage margins unpinned and proposed recording the gap. It
  was cheaper to write the test — and leaving a known-green mutation while the
  same branch adds "compositions that exist in the code and not in the corpus" to
  the taxonomy would have been the exact failure the shape describes.
- **The root's percentage *width* still falls back to the available space** (800 where WebKit gives 400) while its percentage *padding* correctly uses `available.width`. Pre-existing, untouched by this branch, now documented with a measured number and cross-referenced at both sites. **Do not fix one without the other.**
- **BM-4's over-constrained box** is a deliberate, documented divergence.
- **`margin: auto` is inert** — CSS gives it priority over `justify-content`.
- **Content-based cross sizing is still 0** and unreachable by any fixture until M2 measures content.
- **Two known divergences carried from earlier milestones** — FS-9 and AL-4 together state one rule: two independent engines agreeing outrank the spec's letter; one engine alone does not. Do not change either without reading both.
- **`LayoutNodeID` has no generation counter** (m1a ruling C-3).
- **Two guarantees lapse under plausible CI configurations** — the ABI probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is the only live-WebKit consumer. Both must be required, non-gateable jobs.
