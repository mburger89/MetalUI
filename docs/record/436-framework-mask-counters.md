# 436: `FrameWork.maskScopesPushed` and `FrameWork.groupsMasked` (class M, no divergence, no ruling)

Branch `feat/framework-mask-counters`, base master `eb25ea24`. Two public fields, no divergence (242 live, next label 250). Number 435 is reserved by another branch.

**Why.** Alloy wants a regression guard that no full-viewport mask group is drawn: a crossing rounded clip (`CM-B`) or a shape clip (`CM-A`) is drawn as an offscreen group multiplied by its shape, and a clip whose box is the viewport makes that group viewport-sized every frame. `Frame` already counts both (`maskScopesPushed`, `groupsMasked`), but only an in-package test could read them.

**What.** Both are carried exactly as the table counters are: `BuildWork` (`TestingHooks.swift`) takes `frame.maskScopesPushed` and `frame.groupsMasked` when the build is adopted, `TestWindow`'s `pending` sums them over the builds of a presented frame, and `FrameWork` holds them with a doc comment, an `init` argument defaulting to 0 and a term in `+`. Integer reads of counters that exist: no work on the frame, no allocation.

**Observed (`FrameWorkMaskCountersTests`).** A 100 x 60 island clipped to radius 10 around a 92 x 60 child of two leaves clipped to the same radius: the child inside the island (`leading` 0) is 0 scopes, 0 groups. Shifted 10 points in, it overhangs the trailing edge by 2, so its corners cross the island's: **1 scope, 1 group** (one clip pair, one scope; the two leaves are one group because the scope marks its captures with one mask). A child that is merely inset from the corner squares (the first fixture tried: a clipped or unclipped child 4 or 10 points in, full height) is contained by the island's corner discs and counts 0: crossing needs a clip that leaves the other (`Frame.intersectReportingCrossing`).

**Alloy's case (square viewport in a rounded island).** A 566 x 744 island, radius 10, holding an `HStack` of a stripe and a `ScrollView` of 31 pt rows (a viewport clips to its own bounds, zero radii) at full height. Viewport 4 pt inside the left edge: its box overlaps the corner square and its far corner is 11.7 from the centre (r 10), so it crosses, and an idle frame reads **1 scope and 1 group at scale 1 and at scale 2** (the analysis holds). Viewport 10 pt inside both edges: **0 and 0** at both scales. Wiring `maskScopesPushed` to 0 reddens the 4 pt arms.

**Cost.** An idle frame of that fixture on master `eb25ea24` and here: 5 element requests, 324 allocations, 25,906 bytes to 25,922 bytes (the 16 bytes are the two `Int`s in each `FrameWork` the harness stores). No pin moved.
