# Content Sizing — Design

**Date:** 2026-08-26
**Status:** Approved design; implementation plan not yet written.
**Parent spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` (§5 layout, §5.5 measure functions)
**Rulings this milestone serves:** EP-5 (take SwiftUI's answer over CSS's where they differ),
EP-6 (`Column`/`Row` keep `stretch` *because* auto cross resolves to 0 — this milestone removes that reason)

---

## 1. Goal

Give the layout engine a way for a **subtree** to report its own size, so that an
`auto` size measures content rather than resolving to 0.

Today only a *leaf* can answer, through a `MeasureFunction` that no production
code ever attaches. A container cannot answer at all, and four places in the
engine paper over that with a constant:

| Site | Today |
|---|---|
| `FlexBaseSize.swift:43` — §9.2 content branch | `guard let measure = tree.measure(item) else { return 0 }` |
| `FlexEngine.swift:622` — CSS Sizing §4.5 automatic minimum | `guard let measure = tree.measure(kid) else { return nil }` |
| §9.4.8 line measurement — an `auto` cross size | `0` |
| `resolveRootSize` — an `auto` root axis | falls back to the offered space |

The third is a measured divergence from WebKit: a 200×200 `wrap` root holding a
`width: 120px` nested flex container gives WebKit `120×50` and this engine
`120×0`, collapsing the line and stacking the next one on top of it.

**This milestone is a prerequisite, not a feature.** It blocks M2 (text is a leaf
whose size comes from measurement) and it blocks EP-5's stack defaults (a
SwiftUI-style centred `Column` would paint nothing while `auto` means 0).

## 2. Scope

**In:** full intrinsic sizing — the recursion honours `.definite`, `.minContent`
and `.maxContent`, so a container answers the same three questions a leaf does.

**Out, deliberately:**

- **The root's percentage width** (`resolveRootSize` resolving percentages
  against `nil` and falling back to the offered space; WebKit says 400 where we
  say 800). That is a containing-block bug, not a content bug. It moves the
  root's stored size, which every descendant consumes.
- **Ruling BM-4's over-constrained box.** Unrelated: it concerns padding
  exceeding a *specified* size.
- **Structural identity (§4.3).** Split off as its own milestone — different
  module, no shared code.
- **Attaching a real `MeasureFunction`.** That is M2. Containers exercise the new
  path; leaves still have no production caller.

## 3. Architecture

### 3.1 Measure and place

`layoutContainer` splits into two entry points over shared internals:

```swift
func measureNode(_ ctx: LayoutContext, _ node: LayoutNodeID,
                 known: OptionalSizeD, available: AvailableSpaceSize) -> SizeD
func placeNode(_ ctx: LayoutContext, _ node: LayoutNodeID,
               origin: (Double, Double), size: SizeD, containingBlockWidth: Double?)
```

`measureNode` is **pure**: it computes and returns a border box and never calls
`setLayout`. A leaf answers from its `MeasureFunction`; a container answers by
running `collectItems` → `collectLines` → `resolveFlexibleLengths` over its
children and returning the result. Callers cannot tell which happened, which is
what makes all four sites above fixable with one call.

`placeNode` keeps today's behaviour and is the only thing that writes layout. The
recursion at `FlexEngine.swift:960` becomes `placeNode`.

This mirrors Taffy's `RunMode::ComputeSize` vs `PerformLayout` and WebKit's
separation of intrinsic-size computation from layout.

**Rejected alternatives.** A `commit: Bool` dry-run flag on one function makes
every `setLayout` conditional, and a missed one corrupts a real layout during a
speculative measure. A bottom-up pre-pass caching one intrinsic size per node is
wrong for CSS, because min-content and max-content depend on the available space
passed *down*; it works until the first `wrap` container.

### 3.2 `LayoutContext`

A per-run value threaded through the recursion, holding the memo cache and
`rootFontSize` — which currently rides on every signature in the engine and
collapses into this.

Created in `computeLayout`, destroyed with it. **It does not live on
`LayoutTree`.** The tree is storage; a cache outliving a run is the stale-data
shape ruling C-3 spent a milestone closing.

### 3.3 The cache

Memoization is a correctness-of-cost requirement, not an optimisation. Each level
issues three queries per child — min-content, max-content, and the real layout —
so the work multiplies with depth: ~700× at depth 6. Invisible across a
57-fixture corpus of shallow trees, lethal in an application.

**Key:** `(node, known.width, known.height, available.width, available.height)`,
with `Double`s hashed by `bitPattern` so the key is deterministic. A near-miss on
floating-point equality costs a recompute and never a wrong answer — the right
direction for this to fail.

**Soundness** rests on styles not mutating during a run, which nothing enforces
today. `setStyle` gains a `precondition` that no layout is in progress. A style
written mid-layout would hand back cached sizes for the old style, and no fixture
could catch it.

### 3.4 Two hazards to close rather than document

- **Cycles.** `newNode` accepts arbitrary child ids, so a cycle is constructible
  and already hangs today's top-down recursion. Measurement makes it easier to
  reach. Add a depth guard that traps with the node id.
- **Purity.** A `measureNode` that accidentally called `setLayout` would return
  the correct size and pass every golden. A test that measures a subtree and then
  asserts every node's stored `layout` is byte-unchanged is the only thing that
  can see it.

## 4. Blast radius

The largest consequence is not the auto-cross fix. It is that **`min-width: auto`
becomes live for containers** — CSS's default on every flex item, today
floorless because the content suggestion returns `nil`. After this, items stop
shrinking below their content, and goldens across the existing corpus move.

That is why the corpus is regenerated rather than frozen (§5.1).

## 5. Testing

### 5.1 The corpus

1. **Regenerate all 57 fixtures against live WebKit and read the diff as
   evidence.** A golden that moves exercised auto sizing; one that does not,
   did not. The list of non-movers is a map of what the corpus never covered and
   belongs in the decisions doc.
2. **New fixtures** where there is no coverage: a nested container with an auto
   cross size (the divergence repro above); auto height at two levels; a `wrap`
   container where min-content and max-content genuinely differ; and an item
   whose automatic minimum now floors it.
3. **Every new fixture gets its differential.** Change the declaration the
   fixture is named for, regenerate, confirm the numbers move — and **run it,
   never predict it.** The wrapping milestone hand-derived sixteen sibling swaps
   and four were wrong.
4. **Geometry avoiding `x.5`**, per the 1/64 quantization hazard.

Goldens are browser-generated and never hand-edited.

### 5.2 Mutations that must redden

Written as guards up front rather than discovered:

| Mutation | Must redden |
|---|---|
| `measureNode` returns 0 for containers (today's bug) | the auto-cross fixture specifically |
| the cache is made a no-op | a **hit-count** assertion — nothing else can see it |
| the cache is never invalidated between runs | a two-layout test |
| `measureNode` calls `setLayout` | the purity test |
| `.minContent` and `.maxContent` swapped at a call site | a fixture where they differ |

The last is the one expected to survive a weak corpus: the two coincide unless
something wraps.

### 5.3 Documentation that must change

- CLAUDE.md's **auto-cross divergence row leaves** the inert table.
- The `MeasureFunction` / `tree.measure()` row **shrinks** to "leaves have no
  production caller until M2" rather than disappearing.
- **Ruling FS-3** is re-examined: the automatic minimum is
  `min(specified suggestion, content suggestion)` and this milestone supplies the
  half that was missing.

## 6. Exit criteria

- [ ] `measureNode` answers for containers and leaves alike, honouring
      `.definite`, `.minContent` and `.maxContent`
- [ ] The WebKit repro (`120×50` vs `120×0`) matches, pinned by a fixture
- [ ] All 57 existing fixtures regenerated; every moved golden explained in the
      decisions doc
- [ ] Every mutation in §5.2 reddens, measured and recorded
- [ ] Cache hit-count asserted; purity asserted; cycle guard traps
- [ ] `swift test` completes with a **summary line** and the full count —
      taxonomy shape 11
- [ ] `swift build` / `swift test` warning-free; `MetalUILayout` still imports
      only `MetalUICore`
- [ ] The three CLAUDE.md rows in §5.3 updated in the same commits that make
      them true
