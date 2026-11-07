# Record 221: a gradient `foregroundStyle` on text (R4-5 PR D) — DRAFT (run 1)

Branch `feat/text-gradient` (master `d0cceec6`). Rulings `TG-A`..`TG-E` (new prefix; decisions doc `docs/superpowers/2026-11-0X-text-gradient-decisions.md` is run 2's). Divergence **975 narrowed, not retired**. Probe `docs/probes/swiftui-text-gradient.swift` (commit `65537362`). Plan: the reviewed R4-5 PR D plan; the deviations are in section 4.

TODO(run 2): decisions doc, ledger (975 text, `docs/divergences.md`, record 04 section), shards, `decision-prefixes.md`, human-checks group `TG`, SDL tests 22-23, parity frame 19, demo strip, `api-overview.md`, `migration.md` (`Text.foregroundColor` computed; `swift package clean`), README row, `Tasks.md`, `CLAUDE.md`/`AGENTS.md` counts.

## 1. What was measured (probe, compiled `ImageRenderer`, six byte-identical runs, 71 lines)

- `TG0` separates (left B .09, right B .99; control `Color.red` B 0 twice).
- **The span is the ink, not the layout box** (plan expected the layout box): `TG3d` ink .08 vs box .40; `TG2d` vertical ink rows .04-.09 vs line box .31; `TG8x` radial ink .03 vs box .11. A frame (300) and padding are not the span; a container spans each `Text` (`TG4x`).
- **One span per text, not per glyph or line** (`TG1`, `TG2`): wrapped lines share it.
- **Runs (`TG5`)**: the span is the union of the ink of every run carrying the same gradient (`g` beside a red run: its own box; `g,g`: both; `g,green,g`: first and third share one span over all three).
- Decorations follow the gradient and **extend the span** (`TG10`, `TG10v`); an own colour stays. Shadow is the shadow colour (`TG6`); opacity fades once (`TG7`); a level over a gradient parent keeps the gradient at .502 (`TG9`); a bare `Rectangle` takes the gradient (`TG14`). `TG12`, `TG13` not measurable.
- Stop condition P: did **not** fire for per line / per glyph; the rect source *did* change (ink union per equal gradient, not the layout box) as the plan allowed.

## 2. Mutations
TODO: table (branch and spelling), filled below as run.

## 3. The mapping audit
TODO.

## 4. What the code forced
TODO.

## 5. Pins moved
TODO.

## 6. Runs
TODO.

## 7. Not done (run 2)
SDL tests 22-23, parity frame 19, demo strip, docs/ledger.
