# Clipping and scroll — decisions taken during execution

Rulings from the milestone that gave the renderer per-primitive clipping, `Frame` a clip/translate
stack, and the framework its first `ScrollView`. Prefixed **`CL-`** and **lettered** (`CL-A`, `CL-B`,
…) per this repo's convention for `CS-`/`SI-`/`TX-` — a bare `CL-3` is a typo, not a citation. Read
alongside `docs/superpowers/specs/2026-08-24-metalui-design.md` §7.3 (the mechanism this milestone
built) and CLAUDE.md's declared-but-inert table (`Style.overflow`'s row, which this milestone
touched without making live).

## CL-A — clipping is a fragment mask in the instance buffer, not `[[clip_distance]]`

**The design's first draft specified `[[clip_distance]]`** (§7.3, before this milestone). What was
built instead is `contentMask`, an axis-aligned `Bounds` already present on `MUIRect` and `MUIGlyph`
since M0 — round-tripping the ABI and read by nothing (CLAUDE.md's declared-but-inert table, the row
this milestone deleted). Task 3 turned it on in `rect_fragment`; Task 4 mirrored it in
`glyph_fragment`; Task 5 gave `Frame` the CPU-side stack (`pushClip`/`popClip`,
`clipped(to:offsetBy:)`) that fills it every frame instead of the whole-surface default.

**Why the reversal, and it keeps rather than abandons §7.3's actual argument.** §7.3's objection to
scissor rects was never about a fragment mask's correctness — it was about avoiding a state change
that breaks a batch at every clip boundary. A fragment mask riding along in the same instance buffer
as the primitive's other fields changes *between instances of one draw call* exactly as freely as
`background` or `cornerRadii` already do, so it costs nothing a scissor rect's state change would
have cost. `[[clip_distance]]` was rejected for a *different* reason, one a fragment mask does not
share: a clip plane is a half-space, and a `ScrollView` viewport's clip needs to be a rounded rect
the moment `cornerRadius` is added to the container doing the clipping — a small fixed set of planes
cannot express that shape at all, while a mask is just another quantity `rect_fragment`'s existing
SDF machinery multiplies into. `mask_coverage` (`shaders.metal`) is a few lines beside code that
predates this milestone, not a new subsystem.

**What it costs if wrong — and this is a real, currently-paid cost, not a hypothetical one.** The
built mechanism is still rectangular: `Frame.activeClip` is a `Bounds`, with no radius of its own, so
a `ScrollView` wrapped in a rounded `Box` clips its content to a rectangle while its own background
paints a rounded one underneath. A row scrolled to the very top or bottom of the demo's list paints
square into the corner the container's rounded background left transparent — visible in
`Sources/MetalUIDemo/main.swift`'s scroll list, and recorded there and at `Box.cornerRadius`'s own
doc comment. That gap is orthogonal to the fragment-mask-vs-`clip_distance` choice: `[[clip_distance]]`
would not have closed it either, since it cannot express a rounded clip at all. Closing it needs a
masked *shape*, not a masked *rect* — a follow-on, not a reason to revisit this ruling.

## CL-B — `Style.overflow` is written for the model's sake, and the engine reads it nowhere

`ScrollView.requestLayout` sets `viewportStyle.overflow = Axes(both: .scroll)` — the property's first
production write. **Measured during this milestone's design, before the write was even added**: a
probe that removed the equivalent line from the layout under test moved no number the engine
produces. Clipping and scrolling both work in the shipped `ScrollView` — through `pass.clipped(to:offsetBy:)`
and `pass.registerScrollRegion(_:id:axis:)`, called directly from `ScrollView.prepaint`/`.paint` —
and neither consults `Style.overflow` at any point. `grep -rn "\.overflow\b" Sources/` outside
`Style.swift`'s own declaration finds exactly the one write and the doc comment describing it;
nothing reads it back.

**Why write a property nothing reads.** CSS's `overflow: scroll` is what a reader of the style would
expect a scrollable container to declare, and leaving it `.visible` (the default) on a node that
demonstrably clips and scrolls would misdescribe the node to the next person who reads `Style`
directly rather than through `ScrollView`. The write documents intent the way a comment would, at the
cost of looking like it drives behaviour when it does not.

**What it costs if wrong.** Believing this write is load-bearing is the trap: a future container that
wants clipping without going through `ScrollView`'s explicit `pass.clipped(...)` call would set
`overflow: .scroll` and get nothing, silently. CLAUDE.md's declared-but-inert table carries `overflow`
as its own row for exactly this reason — a *write* with no *read* is a sharper trap than a property
nobody touches, because the write is evidence-shaped without being evidence.

## CL-C — `flexShrink: 0` on the content node is load-bearing, and a probe made of fixed-size boxes said otherwise

**This ruling was decided the wrong way once, and the record of the error is the point of it.** It
originally read: *the automatic minimum, not `flexShrink`, is what makes a `ScrollView`'s content
overflow* — and on that reading `contentStyle.flexShrink = 0` was deleted from
`ScrollView.requestLayout` as an inert line. That was wrong. The line is restored.

**What was claimed.** The four-row probe in `ScrollView.swift`'s doc comment (5×40pt rows in a
200×100 viewport) shows rows one and two — `min-height: auto` with `flexShrink: 0` and with
`flexShrink` default — landing the content node at 200 either way, and only row four
(`min-height: 0`, `flexShrink` default) collapsing it to 100. From that: `flexShrink` matters only
where an explicit `min-height: 0` has removed the automatic minimum; `ScrollView`'s content node
never carries one, having no modifier surface; therefore the line is unreachable and inert, and
CLAUDE.md's declared-but-inert table says to delete rather than keep such a line. The required
mutation was run — delete it, run the full 468-test suite of the day, revert — and reddened nothing,
including a differential built specifically to catch it.

**What falsified it.** Every row of that probe is measured on **fixed-height `Box`es, whose
min-content and max-content sizes are the same number.** With nothing between the floor and the base
size, the freeze loop has nothing to shrink, and `flexShrink` is invisible *by construction of the
fixture* rather than by any property of the type. That is exactly the corpus-uniformity hazard
CLAUDE.md records about the 61 empty-div fixtures, reproduced at probe scale — and the mutation
reddening nothing was the tell taxonomy shape 9 describes, not the evidence it was read as.

`flexShrink` is load-bearing in a second case the probe never contained: whenever the content's
**min-content is smaller than its max-content**, which is any content holding text. The automatic
minimum floors the content node at min-content; its flex base size is max-content; the freeze loop
shrinks it from the latter towards the former, and `flexShrink = 0` is the only thing that stops it.
No explicit `min-height: 0` is involved anywhere.

**Measured through `ScrollView` itself, 2026-08-28:**

| probe | line deleted | line restored |
|---|---|---|
| `ScrollView(.horizontal) { Text(…); Text(…) }` in a 200pt viewport | content **200** — equal to the viewport, so nothing to scroll and the indicator is suppressed entirely | content **507.8** |
| `ScrollView(.vertical) { 5 × Text(…) }` in 200×40 | content **80** — half the list unreachable | content **160** |

**The decision.** `contentStyle.flexShrink = 0` stays, and it is now pinned through `ScrollView`
itself by `aScrollViewOfTextDoesNotShrinkItsContentToTheViewport`
(`Tests/MetalUITests/ScrollViewTests.swift`), whose oracle is `CTLineGetTypographicBounds` rather
than anything in this engine. Deleting the line reddens exactly that test, on both of its
expectations. The engine fact the four-row probe *does* isolate — that `flexShrink: 0` also holds a
node open once an explicit zero minimum has removed the automatic one — remains pinned independently
by `flexShrinkHoldsAContentNodeOpenOnceItsAutomaticMinimumIsRemoved`
(`Tests/MetalUILayoutTests/ScrollLayoutTests.swift`), and no element reaches that row today.

**What it costs if wrong.** Concretely, and this is what it cost while the line was absent: a
horizontal `ScrollView` of labels does not scroll at all — its content is shrunk to exactly the
viewport, `scrollable` is 0, and `paintIndicator` returns before drawing anything, so the failure is
a list that silently refuses to move rather than an error. A vertical one loses the tail of its
content the same way. The general lesson is the one the whole repo runs on: **a mutation reddening
nothing is a claim about the fixtures, not about the line** — and a probe built from uniform
content cannot speak for content that is not uniform.

## CL-D — two borrowed M4 primitives, not an animation system

`Frame.timestamp` (the display link's tick, threaded through every element in one frame) and
`Frame.requestAnotherFrame()` (an element's request for another pass) exist because the scroll
indicator's fade needs *some* notion of elapsed time and *some* way to keep the display link running
while it ramps. Both are named in their doc comments as "a borrowed M4 primitive" — inputs a
time-based animation needs, not an animation system. `ScrollView.paintIndicator` computes its own
ramp by hand: `age < 0.6 ? 1.0 : max(0, 1.0 - (age - 0.6) / 0.4)`, a `let` and an `if`, not an easing
curve or a keyframe track.

**Why borrow rather than build or defer.** Building a real animation system to fade one thumb would
be scope creep this milestone does not need; deferring the indicator's fade entirely would leave a
scroll thumb that never disappears, which is a worse UX than a hand-rolled ramp. Borrowing the two
primitives M4 will eventually own anyway keeps the fade honest about what it is.

**What it costs if wrong.** Recorded here so M4's planning does not re-scope `Frame.timestamp` or
`requestAnotherFrame()` as new work, or accidentally change their contract — `Frame.render`'s ordering
(`glyphAtlas.beginFrame()`/`endFrame()` bracketing paint, `timestamp` read once and shared by every
element in the frame) is an assumption `ScrollView.paintIndicator` already depends on. A `Frame` that
started reading a wall clock per element, or that recomputed `timestamp` mid-paint, would desync the
ramp from what every other element in the same frame saw.

## CL-E — scroll chaining is absent by decision, not by oversight

`Window.applyScroll` claims the topmost matching scroll region outright and does not pass a spent
delta on to an ancestor region once the topmost one is at its limit — the way, say, a nested list
inside a page chains to the page's own scroll in a browser. `Window.applyScroll`'s doc comment states
this explicitly: "Not handled: scroll chaining... That is a dispatch concern belonging with the
general hit-test work (§8.1), and this method claims the topmost match outright rather than falling
through."

**Why defer rather than implement.** Chaining is a dispatch-layer feature — it needs the same kind of
walk §8.1's general hit-test registry will do for click/hover, generalized past the scroll-only
registry (`Frame.scrollRegions`) this milestone built. Building a scroll-specific version of that walk
now would duplicate work §8.1 does properly later, for a feature (`ScrollRoutingTests.swift`'s nested
`outer`/`inner` fixtures) this milestone's own tests exercise only as "the topmost region wins, the
other does not move" — chaining was never in scope to begin with.

**What it costs if wrong** — meaning, what a user notices today: a nested `ScrollView` at its scroll
limit absorbs the rest of a wheel gesture and does not hand the remainder to whatever scrollable
ancestor contains it. A trackpad swipe that keeps going past an inner list's end just stops, rather
than continuing to scroll the page around it. This is a known, named gap, not a bug to chase — the
fix belongs with §8.1's hit-test work, not with this milestone's scroll-region registry.

## CL-F — a horizontal `ScrollView` takes `delta.x` only, with no cross-axis fallback

`Window.applyScroll` reads `event.delta.x` for a `.horizontal` region and `event.delta.y` for a
`.vertical` one, chosen by the region's own `axis` (carried on `Frame.scrollRegions`, fixed by a bug
this milestone found and corrected — see `Window.applyScroll`'s doc comment). There is deliberately
no fallback that lets a plain vertical wheel drive a horizontal list, the way some web UIs remap an
unmodified vertical scroll onto a horizontal one when nothing else on the page would consume it.

**Why narrow the semantics rather than add the fallback.** AppKit already remaps components for
shift-scroll on trackpads that report it, so this layer does not need to reproduce that remapping.
Whether a wheel-only device (no shift, no native horizontal gesture) should be able to drive a
horizontal list at all is a UX decision with real trade-offs — it changes what a *vertical* wheel does
to a page that also contains a horizontal list, which is a decision belonging to whoever owns the
overall scroll UX, not to this milestone's wheel-routing plumbing. `aHorizontalScrollViewMovesOnDeltaXNotDeltaY`
(`Tests/MetalUITests/ScrollRoutingTests.swift`) pins both halves: `delta.x` moves it, and a nonzero
`delta.y` sent at the same time does not.

**What it costs if wrong.** A horizontal list embedded in a vertically-scrolling page does not respond
to an ordinary vertical wheel gesture at all — only a native horizontal one (a trackpad swipe, or
shift-scroll, which AppKit already remaps to `delta.x` before this code ever sees it) moves it. A
future caller who wants the fallback UX must add it explicitly at `Window.applyScroll`; it is not
lurking half-implemented anywhere in this milestone's code.
