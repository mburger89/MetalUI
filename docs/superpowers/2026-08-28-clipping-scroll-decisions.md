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

## CL-C — the automatic minimum, not `flexShrink`, is what makes a `ScrollView`'s content overflow

**The design's first draft named `flexShrink: 0` on the content node as the mechanism** that holds a
`ScrollView`'s content open past its viewport, an item that has shed the automatic minimum via an
explicit `min-height: 0` and would otherwise be shrunk back down by the freeze loop. Measured against
the actual four-row probe in `ScrollView.swift`'s doc comment (5×40pt rows in a 200×100 viewport):
rows one and two — `min-height: auto` (the default) with `flexShrink: 0` and with `flexShrink`
default — **agree with each other regardless of `flexShrink`**, both landing the content node at 200
(overflowing). Only removing the automatic minimum (`min-height: 0`) changes the answer, and only
*then* does `flexShrink` start to matter (row three vs. row four: 200 vs. 100). CSS Sizing §4.5's
automatic minimum — the content-based floor `min-width`/`min-height: auto` resolves to by default —
is therefore the **sole** mechanism by which `ScrollView`'s content node overflows its viewport; the
content node never carries an explicit `min-height: 0` at all, so row four (where `flexShrink` would
matter) is unreachable through this type by any caller.

**`flexShrink: 0` was written, measured, and deleted rather than kept "for later."** The required
mutation — delete the line, run the full 468-test suite of the day, revert — reddened nothing,
including a differential built specifically to catch it. Being unreachable rather than merely
untested, it was removed: CLAUDE.md's declared-but-inert table exists precisely because a line that
compiles and does nothing reads as considered and invites the next container to cargo-cult it. The
engine fact `flexShrink: 0` would have been worth specifying *if* reachable — that it holds a node
open once an explicit zero minimum has removed the automatic one — is real and stays pinned
independently of `ScrollView` by `flexShrinkHoldsAContentNodeOpenOnceItsAutomaticMinimumIsRemoved`
(`Tests/MetalUILayoutTests/ScrollLayoutTests.swift`).

**What it costs if wrong.** A reader who assumes `flexShrink` is doing the work here and "fixes" a
future regression by touching it will change nothing, because the content node's `flexShrink` is
never read for this purpose in the first place. The floor is `min-height: auto`'s automatic minimum,
computed from the rows' own stacked heights; that is the line to look at.

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
