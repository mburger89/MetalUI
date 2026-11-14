# 299 - A tab strip's bar and selected-tab paint: `stripBackground(_:)`, `selectedTabFill(_:)` (`TBS-N`)

Branch `feat/tabstrip-background` from master `c3b22006`. Alloy gap G46 addendum, class M, no divergence label. Ruling `TBS-N` in `docs/superpowers/2026-11-07-tab-strip-decisions.md`.

**Why.** Alloy sets a `TabStrip` inside a glass bar, but the strip hard-coded `.background(.surfaceSecondary)` on its bar and `.background` on the selected tab, so it painted a flat band over the glass.

**Change.** `TabStripPaint` (`.automatic`, `.clear`, `.color(_:)`, `.material(_:)`) and two instance methods, `TabStrip.stripBackground(_:)` and `.selectedTabFill(_:)`, spelled like `selectedTabShape`. `.automatic` is today's look: a scene dump of the default strip (light and dark, each tab selected, a dirty tab) is byte-identical before and after. `.clear` on the bar attaches an empty group, so no rectangle at all is drawn; a material fill on the selected tab goes through the shape path (`TabStripFill`), full bleed for `.rectangle`. Both paints take part in `==`. Hover wash, hairlines, close buttons, ink, focus and accessibility untouched. The name avoids `background`, which would shadow the generic modifier.

**Tests** (`Tests/MetalUITestingTests/TabStripPaintTests.swift`, 7): defaults and `.automatic` signature equal and the theme colours; `.clear` bar has no 500 x 32 rect and no backdrop; colour and material bars; a green selected fill in the rectangle, capsule and rounded shapes; a clear and a material selected fill; a theme switch repaints the automatic paint and not a custom colour; equality. Mutations tried (clear falling to the surface colour, paints left out of `==`, the fill colour ignored, the automatic bar's alpha changed) each reddened the named test.

**Human check** `TBS7` (group TBS).
