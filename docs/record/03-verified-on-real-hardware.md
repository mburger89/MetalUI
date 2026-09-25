## Verified on real hardware

`swift run MetalUIDemo` was run and inspected on a Retina display: the window
shows the centred rounded rect with its antialiased border, and the close button
quits the process.

**Text verified on 2026-08-28 — M2's exit criterion, and the only check no test
here can perform.** A human ran `swift run MetalUIDemo` and reported it looks
right: the sidebar label, the 22pt heading and the wrapping paragraph all render
legibly, and the paragraph re-wraps at word boundaries when the window is
resized.

**The look was directed rather than general**, because §4.2 of the M2 spec names
three failure modes no test in this repo can see — a wrong glyph from an atlas
key collision, fuzzy or wobbling text from a missing subpixel variant, and
intermittent blank runs from eviction during a frame. **Two of the three remain
unchecked and it is worth knowing which**: wobble needs sub-pixel *motion* and
neither a static look nor a screenshot can show it, and eviction blanks are
absent by construction in M2 rather than tested, since nothing calls
`evictUnusedSince`. The cross-*family* key collision is also unexercised — the
demo uses one font family.

**A second look followed the line-height change** (`ceil(ascent + descent +
leading)`, 15.3105 → 16.0 at 13pt): the leading now reads correctly against
typical Mac apps, which is what prompted the change. Whether the pixel-alignment
argument for rounding is *visible* was not established either way.

**Re-verified on 2026-08-27 after ruling EP-8 made `Column`/`Row` centre on the
cross axis**, because that ruling's failure mode is an *invisible rectangle* and
no test in this repo can see one: a human ran the demo and reported it looks
right — nothing vanished, the sidebar rows and the separator still fill their
containers through their new explicit `.alignItems(.stretch)`, and resize and the
light/dark toggle still work.

**That was M0's demo, and it is not what `MetalUIDemo` draws today.** The demo
was replaced by the element pipeline's — a four-level nested flex layout of
themed, rounded, background-filled boxes with a light/dark switch — and **it was
run and inspected by a human on 2026-08-26, who reported it works as expected**:
the nested layout renders, it reflows live while the window is dragged, and the
light/dark switch works. That closes milestone 1's exit criterion. Two specifics
of the M0 sentence above are stale rather than wrong: the rect it describes was
inserted as an `MUIRect`
directly, through an `App.openWindow` overload that no longer exists,
and **no element can draw a border at all.** `Frame.fill` is the only production
path into a `Scene` and it hard-codes `borderColor: .transparent,
borderWidths: 0`; the blocker is the resolved *width*, not the colour, and it is
recorded at `Frame.fill`. The renderer primitive still supports borders — M0's
demo is the proof — but nothing above the renderer can ask for one.

**Erratum 2026-09-14 (at `7cfcddc`; record §09):** "no element can draw a
border" is no longer true. `Frame.fill` takes `borderColor:`/`borderWidths:`
(`7c71996`), and the proposal-path `.border` modifier draws one. Legacy
elements still pass none, and `borderWidth(_:)` still paints nothing.

**What the human check establishes is a property of `AppKitPlatform`, not of
what the demo draws — and no test can establish it.** `MetalLayerSurface` vends drawables whether its `CAMetalLayer` is
attached to the view or orphaned, so reversing the `layer` / `wantsLayer`
assignment order in `AppKitPlatform` renders perfect pixels into a texture nobody
sees — and the whole suite still passed when that was measured, at 342 tests
(**811 today**, re-run 2026-09-03 at the `Component` milestone's whole-branch fix wave; the count is quoted so the measurement can be
dated, not because 342 is a property of anything — and the "today" figure has to
be re-taken with the rest, which it was not at 739 for two milestones). If you
touch that ordering, re-run the demo
and look at it; the suite will not tell you.

**What the machine established about text before that look, and it is a
different thing from the look.** A `Text("Hi Wag")` at 22pt rendered through a
real `Renderer` into a real `Window`'s drawable and read back produces
**legible glyph shapes in the right order at the right advances** — the readback
was printed as ASCII art and the word was readable. That rules out the gross
failures (nothing drawn, every glyph stacked, the atlas sampled at the wrong
scale) and rules out none of §4.2's three, which is why the human look above is
the exit criterion and this is not. The assertable half of that technique is
kept as a test — `theWindowsPixelsAreExactlyTheGlyphBitmapsItsSpritesStandFor`,
which compares every unambiguously covered byte of the drawable against the
glyph's own rasterized bitmap — and its doc comment names the three failures it
still cannot see, and why each one hides from it.

**A race the whole-branch review found, now closed — and the way it is closed is
the part to know before touching the renderer.** `Window.drawFrameIfNeeded`
commits a frame's command buffer and never waits; there is no semaphore on the
live path (`grep -n "waitUntil" Sources/` finds one line, in
`Renderer.renderOffscreen`, which is test support). `renderer.upload` used to
`texture.replace` **in place** on the persistent `.shared` atlas texture, so the
frame that packed a new glyph wrote pixels the previous frame's draw could still
be sampling — one torn glyph, intermittently, on exactly a resize or a
font-size change. The atlas was the only resource exposed to this: everything
else `encode` binds is a fresh per-frame `makeBuffer`.

**The fix is an invariant, not a lock**: `Renderer.atlasTextureWasEncoded` is set
when the texture is bound, and a texture is written only while that is `false`.
A dirty upload after an encode therefore allocates a *replacement* and fills it
from the whole atlas; the old object stays alive as long as the in-flight command
buffer retains it, which is Metal's job. Steady-state frames allocate nothing —
that is what the `dirtyRect != nil` conjunct in `upload` buys, and dropping it
churns a full atlas per frame.

**What is tested is the invariant, not the race** — the race is a GPU-timing
window and `renderOffscreen` waits, so nothing here can reach it, exactly as with
§4.2's three. `aDirtyUploadAfterEncodingReplacesTheTextureRatherThanWritingIntoIt`
pins both halves (the texture is replaced, *and* the replacement carries the
whole atlas), and four mutations redden it and nothing else. **Spec §4.2 does not
list this failure class**, which is worth knowing because that list is the basis
on which M2's risks were accepted — it was three, and the true count of things
that can produce a wrong glyph with no assertion able to see it was four.

**A thing no test can establish, and this one is a live release trap.**
The `MeasureFunction` a `Text` attaches (`Text.requestLayout`) reduces to
`SizeD` inside `MainActor.assumeIsolated`, because the shaping cache is
`@MainActor` and a `ShapedText` may not cross an isolation boundary. That is
sound **only because `computeLayout` runs synchronously inside
`Frame.computeRootLayout`, which is `@MainActor`** — the engine is non-isolated
code executing on the caller's thread, not a hop. Drive layout over a tree
holding a text leaf from **any other executor** — a background actor, a
`Task.detached`, the 4 MB worker thread `LayoutContext`'s depth test already
spins up — and `assumeIsolated` terminates the process. Nothing in the repo can
notice: every existing off-main-actor layout builds its own leafless tree, and
a test that got this wrong would crash the run rather than redden. If layout
ever moves off the main actor, the measure closure is the first thing to
rewrite.

**That paragraph named ONE `assumeIsolated` site and there were FOUR for one
milestone; it is THREE now, and the fourth's removal is the point of this
correction rather than a quiet renumbering (ruling `RX-J`, amended by the
tokenizer-counter flake fix).** A section naming one of several reads as
though the others were a different kind of thing, which is why they are
listed together at all. Re-counted with `grep -rn "assumeIsolated" Sources/`,
which returns **seven** lines today, of which **three are calls** — down from
eleven and four at the count this paragraph originally took. Run it and read
the lines rather than trusting either number — most of them are doc comments
and that half moves whenever the prose does, which is the failure the
`evictUnusedSince` row below was caught by twice. **"Three call sites" is the
claim**; here they are:

- **`Sources/MetalUI/Text.swift:217`** — the live trap the paragraph above
  describes. **Unguarded**, and sound only by the `computeLayout`-runs-on-the-
  caller's-thread argument. This is the one to rewrite.
- **`Window.markDirtyFromObservation`** (`Sources/MetalUI/Window.swift`) —
  inside its synchronous branch. Guarded by a `Thread.isMainThread` predicate,
  with the `Task { @MainActor }` fallback as the other arm. Collapsing the two
  arms to this one alone is the SIGTRAP result recorded in the reactivity
  bullet.
- **The demo's `atexit_b` counter-summary hook** —
  `atexit_b { MainActor.assumeIsolated { printReactivitySummary() } }` in
  `Sources/MetalUIDemo/main.swift` — safe because `atexit` handlers run on the
  thread that calls `exit()` and both quit paths (the **Q** binding and the
  window's close button) go through `NSApplication.shared.terminate(nil)` on the
  main thread.

**The fourth — `Sources/MetalUIText/UnbreakableRuns.swift`'s
`unbreakableRunCalls` guard — is GONE, and it was removed rather than fixed in
place, because the guard it sat under was never the actual defect.** It read
"Guarded by `if Thread.isMainThread`, so the assumption cannot fail," and that
was true and beside the point: the guard made the *write* safe from a
nonisolated caller, but the counter it protected was a `@MainActor` **global**,
and two `@MainActor` **tests** running under a plain, parallel `swift test`
could still race each other's reset-and-assert windows on it — measured, **8
of 10** runs of `theRunCounterIgnoresCallsMadeOffTheMainThread` failed under
plain `swift test` at this repo's HEAD before the fix, always with the count
higher than expected. `--no-parallel` never reproduced it, which is why the
flake stood unnoticed. The fix replaced the `@MainActor` global and its
`Thread.isMainThread`/`assumeIsolated` guard with a `@TaskLocal`
`Shaper.runCallCounter: RunCallCounter?` each caller binds its own instance
of — visible only within the binding task and its non-detached children, so
concurrent tests cannot see each other's window at all. With no shared mutable
state left to protect, there is nothing for `assumeIsolated` to guard, and the
call site is gone rather than re-guarded. See `UnbreakableRuns.swift`'s own
doc comment for the full correction, kept in place with the superseded
reasoning still visible rather than deleted.

**One of the three remaining is guarded by `Thread.isMainThread`
(`Window.markDirtyFromObservation`), one by an argument about where `exit()`
is called from (the demo's `atexit_b` hook), and exactly one by nothing.**
That last one is `Text.requestLayout` and it is the only live trap; the other
two are recorded so that a reader greping for `assumeIsolated` finds an
explanation at each hit rather than one unexplained and one documented.

**Erratum 2026-09-14 (at `7cfcddc`; record §09): there are FOUR call sites
again, and TWO are unguarded.** `ProposalText.requestLayout`'s native measure
closure (`Sources/MetalUI/ProposalText.swift:49`, commit `4bda3d3`) wraps its
body in `MainActor.assumeIsolated` with no guard. It is sound only because
`LayoutTree.computeNativeLayout` runs synchronously inside the `@MainActor`
`Frame.computeRootLayout`, which is the argument above, applied to the second
engine. `Text.requestLayout` is now at `Text.swift:237`, not `:217`. "Exactly one
by nothing" and "the only live trap" are false. Moving either engine off the
main actor means rewriting both closures first.

**Clipping and scroll verified on 2026-08-28 — this milestone's exit criterion,
and it took three looks to close.** A human ran `swift run MetalUIDemo` and
reported, on the third: scrolling works as expected with no intermittent issues,
and the scroll indicator is correctly clipped by the container's rounded corner.

**The first two looks each found a defect nothing in the 501 tests could see,
which is the entire argument for this section.**

1. **Odd text wrapping in the list rows.** Chased to a mechanism recorded as
   **divergence 8**, and it was PRE-EXISTING — measured byte-identical at this
   branch's base `ba22e4a` with no `ScrollView` in the probed tree. The branch's
   only contribution was putting 40 shrink-wrapped strings on screen at once,
   turning a per-string coin flip into something unmissable. **FIXED on
   2026-08-30 and divergence 8 is retired** — `Text.paint` wraps at the width
   layout measured at rather than re-deriving one from the rounded box.
   Re-measured on this exact shape: **31 of these 40 rows wrapped before the fix
   and 0 after.** The entry is gone from the divergence list; label 8 is retired
   and never reused, and the retirement is recorded in that section's header.
2. **"The ScrollView is not rounded, it has hard edges"**, then **"the scroll bar
   is painted outside the corner"** — both real, both fixed here (`f081b9d`,
   `55ed142`). The first exposed a contradiction in this milestone's own spec:
   §1 scoped rounded clip corners *out* while §3.1 justified choosing a fragment
   mask over `[[clip_distance]]` *because* it could clip a rounded container. The
   mechanism was chosen on a capability the same document excluded.
3. **"Scrolling stopped working intermittently."** The offset was clamped on
   *read* and unbounded on *write*, so overscroll banked an invisible dead band
   and reversing events spent themselves unwinding it (`19f55f7`). Measured: 20
   events of −37 into 80pt of real travel stored **740**, and 17 of the next 20
   reversing events moved nothing. Chasing it found a second defect the human had
   not reached yet — the indicator never appeared after ~1s idle, because its fade
   clock was stamped from a display-link timestamp that freezes while the link is
   paused (`329fa04`).

**What the look established that nothing here can: scroll direction.**
`Window.applyScroll` subtracts the delta, and AppKit folds the user's
natural-scrolling preference into that delta's sign — every test pins the
arithmetic against a synthetic delta whose sign the test itself chose. Only a
human on a real trackpad can say which way the list actually moves. The human
also reported that apparent tearing was the wrapping rather than real tearing.

**Every scroll look recorded here was on a trackpad, and that hid a unit bug until
the 2026-09-10 review.** `NSEvent.scrollingDeltaX/Y` is in points only when
`hasPreciseScrollingDeltas` is true (trackpad, Magic Mouse); a conventional wheel
mouse reports LINES. `MetalHostView.scrollWheel` copied the field as points, so a
wheel moved content a tenth as far per line as `NSScrollView` (whose
`verticalLineScroll`/`horizontalLineScroll` default to 10.0). It now converts at
the AppKit boundary through `MetalHostView.scrollDelta(x:y:precise:)`, pinned by
`aNonPreciseScrollDeltaIsScaledFromLinesToPointsAndAPreciseOneIsNot` (the
function) and `aWheelMouseEventReachesOnInputInPointsAndATrackpadEventIsUnchanged`
(real `NSEvent`s through the override). The unit is measured with synthesized
`CGEvent(scrollWheelEvent2Source:units: .line …)` events converted with
`NSEvent(cgEvent:)`: `hasPreciseScrollingDeltas` is false and `scrollingDeltaY` is
the raw line count. **What a physical wheel produces per detent after the window
server's scroll acceleration is not measured**, so how far one click moves the
list on screen is still a look. It is open in the human-verification table.

**What it did NOT establish, and these stay looks forever by construction**
(`docs/superpowers/specs/2026-08-28-clipping-and-scroll-design.md` §9): clip-edge
antialiasing *quality*, whether the fade *timing* feels right, and whether
scrolling feels native. A positive report closes the exit criterion and closes
none of those three.

**Stack's layering was confirmed on 2026-08-28 from a RENDERED READBACK, not
from the running app, and the distinction is the point of this entry.**
`Sources/MetalUIDemo/main.swift`'s main pane now opens with a `Stack` in place
of the plain accent hero box: a 360×128 backdrop, a 160×72 panel and a 28×28
numeral badge, centred on one another and declared back-to-front.

**What was actually checked.** A throwaway harness built that same `Stack`,
drove it through a real `Frame` and a real `Renderer.renderOffscreen`, wrote the
BGRA readback to a PNG, and a human looked at the image and confirmed it matched
expectation. The geometry it produced, at scale 2: backdrop `(100, 72) 720×256`,
panel `(300, 128) 320×144`, badge `(432, 172) 56×56` — all three concentric on
`(460, 200)` — in two draw runs, the glyph last.

**That readback was real evidence about z-order and it was NOT the exit
criterion.** It goes through the production `Scene`, draw list and shaders, so an
inversion would have shown. But `renderOffscreen` is the same instrument M2's
ASCII-art glyph readback used, and this file already records that such a readback
"rules out the gross failures and rules out none of §4.2's three". What it could
not see: compositing against the rest of the window, the layer's Display P3
colorspace (divergence 1 — colours render more saturated than the hex implies),
and the appearance at a real display's scale factor.

**The exit criterion is now CLOSED, by a look on 2026-08-28.** A human ran
`swift run MetalUIDemo`, was asked to look at one specific thing — the `Stack`
hero's z-order, the badge on the panel and the panel on the backdrop — and
reported it looks good.
`docs/superpowers/specs/2026-08-28-stack-container-design.md` §7 item 8 is
**closed**.

**What that look established, and it is the three things the readback could
not.** Z-order observed **through the real window** rather than through an
offscreen texture: composited against the rest of the app, at a real display's
scale factor, in the layer's own P3 colorspace. It is the first and only
observation of `Stack`'s paint order outside `renderOffscreen`.

**What it did NOT establish, and this is the part to be precise about.** The
build the human ran **predates commit `ef7f899` and contained no modal** — no
`Deferred`, no absolutely-positioned box, no scrim. It closes **nothing** for the
absolute-positioning milestone, whose own entry below stands unchanged and open.
A look at one build is evidence about that build.

**It was also, very nearly, the last un-scrimmed look this demo would ever get.**
The modal as first written was always on, laying a translucent wash over the
whole window — and this one file carries four milestones' exit criteria,
including M2's, which is literally a contrast judgement. The modal is gated
behind the **M** key for that reason; see `showModal` in
`Sources/MetalUIDemo/main.swift`.

**Z-order is why that criterion exists, and it is worth restating precisely.**
A `Stack`'s children are placed independently of paint order —
`positionStackItems` never reads which child was declared first — so a
regression reversing paint order would move not one number any test or golden
checks: every rect's `(x, y, width, height)` is identical whichever
child painted first. (This read "the 739 tests or 81 goldens" — the figures at
the input-and-state milestone — and was still saying so two milestones later at
782 and 87. The **claim** is that nothing in the suite can see paint order, and
it does not depend on the suite's size; quoting a count here only gave the
sentence a way to rot. Dated counts belong in the Build section.) **Two artifacts have ever observed the property and both are
outside the suite**: the offscreen readback, once, by hand, and the human look
that closed the criterion. Nothing automated has seen it or can.

**Absolute positioning and `Deferred` — failures 1 and 2 are CLOSED by
measurement of a human's screen recording; 3 and 4 are still OPEN.**
`docs/superpowers/specs/2026-08-28-absolute-positioning-design.md` §6 item 7
asks for a modal in `MetalUIDemo` that is positioned against the window,
painted over everything, and escaping a `ScrollView`'s clip — **and a human to
run it and report**.

**Read how this was closed before trusting it, because it is a weaker
instrument than the `Stack` entry above and was obtained by accident.** The
human ran the demo with the modal up and recorded the screen — *for an
unrelated reason*, to show resize stutter — and never reported on the modal at
all. Failures 1 and 2 were then settled by sampling pixels out of that
recording, not by anyone looking and saying it was right. What makes it real
evidence rather than an assumption is that one token appears at two
brightnesses in the same frame: the modal panel measures `#141A28` against
`.surface`'s undimmed `#161C2E`, while the main pane *behind* the scrim
measures `#0D1118` against the `#0D101B` that `.surface` blended with a 42%
black scrim predicts. The ratio between them is 0.60-0.65 where the scrim's
alpha predicts 0.58, the excess being the recording's own gamma. The top bar is
dimmed too, so the scrim reaches the window's edges rather than the scroller's
420pt strip, and the panel sits visibly over rows 6-9, which are declared after
it.

**The build in that recording is no longer the build a human would run**, and
one of the four failures below has changed since. The measure-performance
milestone replaced the demo's `for` loop over 40 rows with a `List` of **500**,
windowed to the visible slice. The rows are still declared *after* the modal, so
failure 2 reads exactly as written; failure 3 (does the modal move when the list
scrolls) is if anything easier to judge with 500 rows of travel underneath it.
**Failure 4's expected answer INVERTED in the input-and-state milestone** — the
scrim now registers a click target, so the list must no longer scroll under it;
see that item for both halves of the change. Nothing about `Deferred`, the
hoist or the clip reset changed.

**What that leaves genuinely unobserved is failures 3 and 4**, because the
recording contains no scrolling — nobody has seen whether the modal stays put
while the list moves, or what a wheel over the scrim does. Those still need the
run below, and failure 4 is now a sharper question than it was: it has a right
answer rather than an expected report. Note also that dark-on-dark dimming is very hard to judge by eye
with no undimmed reference in frame: a first pass over these same frames
concluded the scrim was **missing**, and only measurement corrected it. A human
report of "I see no scrim" should be measured before it is believed.

**Where it is, and the key that shows it.** Inside the demo's `ScrollView`,
declared **before** the `List` that builds the rows: a `Deferred` wrapping a `Stack` that is
`.position(.absolute).inset(Pixels(0)).background(.scrim)`, holding a 360pt
centred panel. Absolute with all four insets given and an `auto` size makes it
stretch across its containing block, which — nothing between it and the root
being positioned — is the whole window.

**It also carries `.onClick { showModal = false }` as of the input-and-state
milestone**, which is what makes it an *opaque hit target* and therefore what
inverts failure 4 below. Clicking the scrim dismisses the modal; the panel
inside it carries a no-op `.onClick {}` so that clicking the panel does not.
That absorber is not decoration — a container registers before descending, both
sit on the same hoisted layer, and there is no click chaining, so the panel's
later registration wins the tie-break and the scrim never sees it.

**It is off by default and the M key toggles it.** The look therefore has an
instruction: run the demo, press **M**, and watch the transition in both
directions. Two reasons, and the second is the better one. This file carries
four milestones' exit criteria and an always-on translucent scrim would make
every future look pay for this one — M2's is a *contrast* judgement, "the
paragraph renders legibly". And toggling makes **this** criterion stronger:
"the modal covers the window" and "the modal replaced the window" separate by
observation across the transition, rather than by inferring one from the
scrim's alpha.

**The key still works and the mechanism underneath it changed.** M is now a
`Binding("m", ToggleModal())` on the window's `Keymap`, handled by
`Window.onAction`, rather than a `switch` on `charactersIgnoringModifiers` in an
ad-hoc `onInput` — which is gone from the demo entirely, along with the false
sentence it carried ("there is no hit-testing in the framework yet"). Space
moved the same way. Clicking the scrim also dismisses now, so a human has two
ways to close it.

**What a human has to look at, stated as four separable failures.**

1. **The scrim covers the whole window**, not a 420pt-wide strip. Cropped to the
   scroller's viewport means the portal did not reset the clip.
2. **The panel and the scrim paint over the list rows**, which are declared
   *after* the modal. Rows on top means the layer did not hoist.
3. **The modal does not move when the list scrolls.** Sliding with the content
   means `pushRootClip` reset the clip bounds but inherited the accumulated
   offset (ruling AP-I) — half a portal.
4. **Wheel over the scrim with the modal up, and report whether the list moves
   underneath it. THE EXPECTED ANSWER INVERTED with the input-and-state
   milestone, and this item is now a pass/fail rather than a report.** The list
   must **not** move. A human reporting that it still scrolls under the modal is
   reporting a regression, not confirming a limitation — which is the opposite
   of what this item said for three milestones.

   **Two things changed and both were needed.** The framework grew the general
   hitbox list this item used to say nothing short of would change the answer
   (design spec §8.1's, folded so that a scroll region *is* a hitbox with an
   axis attached), so a wheel event now stops at the topmost opaque hitbox and
   scrolls only if that record is itself a scroller. And the demo's scrim, which
   registered no hitbox at all — `Deferred` and `Box` contribute no
   `insertHitbox` call on their own — gained `.onClick { showModal = false }`,
   which is exactly what makes an element an opaque hit target (ruling IN-W).
   `Deferred` has hoisted it to the root layer over the whole window, so it
   outranks everything beneath it.

   **The old sentence was wrong in one further way worth keeping**: it said
   `Frame.scrollRegions` "is the only hitbox list this framework has". That
   accessor is now a derived view with **zero** production readers and has a row
   in the inert table; `Frame.hitboxes` is the list.

   The neighbouring case an earlier review fixed still holds — a scroller
   *inside* a `Deferred` outranks one it paints over, because the registration
   carries its layer.

   **The cost of the same rule, and it is divergence 16**: a button inside a
   `ScrollView` swallows that scroller's wheel over its own rect, where a browser
   scrolls. The demo's counter is in the main pane and not in the list for
   exactly that reason.

**Nothing in the suite can see any of the first three, and the reason is the same one
`Stack`'s entry gives.** A `Deferred` contributes no layout node, so its
subtree's `(x, y, width, height)` are byte-identical whether or not it hoists
and whether or not it escapes; every test and every golden would stay green
under a regression in either half. (This quoted "the 739 tests and 81 goldens",
stale by two milestones at 782 and 87 — see the `Stack` z-order paragraph above
for why the count was dropped rather than refreshed.) The scene-level tests in `DeferredTests.swift`
assert the layer and the mask on synthetic frames, which is real evidence and is
not the same as the composed window.

**And one thing the look will not establish either.** Whether escaping the clip
is what a *user* wants in a given case is a design question, not a mechanism —
design spec §5 names it as untestable up front, and a positive report does not
close it.

**Why the scrim is translucent rather than opaque** (`ColorToken.scrim`, 0.32 in
light and 0.42 in dark): an opaque one makes "covers" and "replaced"
indistinguishable in a still frame. Gating it behind M is what keeps that choice
from taxing every other look in this file.

**Measure-path performance — the exit criterion is CLOSED for release, by a
human on 2026-08-29, and the report came with a boundary attached.** Design
spec §9 item 6 asks for a human to run the demo **in both debug and release**,
drag the window edge, and report whether the resize stutter is gone.

**What they said, quoted rather than paraphrased**: release "works much
better", and the residual is "almost imperceptible — it takes me trying to
stretch it across my whole screen to see a tiny bit of stutter."

**That last clause is the useful half, because it names the remaining cost's
shape.** Stretching the window to full screen makes the viewport TALLER, so
more rows intersect it, so `List` builds more of them per frame — roughly 13
rows at the demo's default height against ~50 at full screen on a large
display. Windowing makes a frame cost O(visible), not O(1): a residual that
scales with window HEIGHT is exactly what the design predicts and is the
boundary of what this milestone bought. A residual that scaled with the
**row count** would have been a defect, and 500 rows is what the demo ships
precisely so that would have shown.

**What this does NOT close, and the distinction is the usual one.** The human
reported on release. **Debug was not separately reported**, and the machine says
debug carries a flat ~3.2x constant factor — 5.060 ms against release's 1.273 at
500 rows — so a debug run is expected to be worse and nobody has said by how
much. The other three report items — a missing, blank or late row at the bottom
edge while scrolling; reaching row 500 cleanly; and the cold-frame launch hitch
(~188 ms debug, ~76 ms release, ruling MP-I) — **were not reported on either
way**. Read the criterion as closed for the question it was written to answer
and open on those four points.

**What the machine established instead, and it is a different thing.** The demo
tree's **steady-state** release frame, measured through a real `Frame.render` on
MacBookPro18,2 / Apple M1 Max, is **1.279 ms at 40 rows and 1.273 ms at 500** —
against **5.366 ms and 50.498 ms** for the same tree at this milestone's base
commit. That closes exit criterion 4 (under 8.33 ms) on the **warm** frame, and
criterion 5 (a long list costs what a short one costs) by measurement. The
**cold** first frame is a different number and is recorded at ruling MP-I: 76.26
ms at 500 rows in release, 188.30 in debug, because that frame builds every row.

**The tail was checked, not just the best**, which is the statistic a stutter
milestone actually needs — a best-of-N hides exactly the frames a human sees as
a hitch. Over the full distribution the flatness holds at every percentile: 40
rows median 1.305 / p99 1.423 / worst 1.427 ms, 500 rows median 1.294 / p99
1.314 / **worst 1.330** ms. The 500-row tail is *tighter* than the 40-row one,
and the worst frame measured at either count is under a sixth of the 8.33 ms
budget.

**And the cost WHILE SCROLLING was finally measured, which is the interaction
this milestone is actually about — every figure above is a static tree.** Same
machine, release, `demoLikeRows(500)` through a real `Frame.render` with the
`StateTable` and `ShapingCache` threaded across frames the way `Window` threads
them, 294 timed frames after ten warm ones, the scroller's stored offset
advanced by a fixed step each frame:

| run | median | p99 | worst | frames the sweep fired on |
|---|---|---|---|---|
| static (offset never moves) | 1.073 | 1.147 | 1.370 ms | 0 |
| scrolling 4pt/frame | 1.171 | 1.381 | 1.498 ms | 1 |
| scrolling 45pt/frame (a fling) | 1.385 | 1.562 | 1.569 ms | 15 |

**That is stronger evidence for criterion 4 than the static figure**, and it
closes a deferred question about whether the generation sweep costs anything in
practice: the run that swept fifteen times has a *tighter* tail than the run
that swept none — a second static run on the same instrument produced a 2.611 ms
outlier, larger than any frame in either scrolling run. Scrolling costs about
0.1-0.3 ms more than sitting still, entirely from cache misses as new rows enter
the window, and the worst frame measured anywhere is under a fifth of the 8.33
ms budget. Resident cache entries move with scroll speed as expected (64/16
static, 110/58 at 4pt, 186/253 at 45pt) and stay under `sweepThreshold`.

**These are this machine's numbers taken with this harness, and one earlier set
did not reproduce.** The whole-branch review reported a median of 0.826 ms over
294 scrolled frames with the sweep firing on 3; re-measured here the medians
came out 0.2-0.6 ms higher and the sweep count is a function of the scroll step
rather than a constant. Nothing about the conclusion changes — every figure in
both sets is far inside budget — but the table above is the one that was
measured by the method it describes, and a re-run should reproduce *it*.

**None of it says anything about criterion 6**: a frame budget met in a harness
is not a window that feels smooth under a drag, exactly as §9 item 6 says.

**Why only a human can close it, stated as a mechanism rather than as
deference.** Resize stutter is produced by the *whole* loop — AppKit's
live-resize run loop mode, the display link, drawable acquisition and GPU
submission — and every number above excludes all four; `renderOffscreen` and a
timed `Frame.render` both stop at the CPU boundary (divergence 3 of design §10
records that exclusion up front). And the demo now carries a second thing worth
a directed look for the same reason `Stack`'s z-order needed one: with a
`List`, rows appear and disappear as the window moves, and a window whose
overscan is too small shows a strip of unbuilt rows for a frame (divergence 13).
No assertion in the suite can see either. (This said "the 739", stale by two
milestones; the claim is about coverage, not about size.)

**What a human must do, and what to report.** Run `swift run MetalUIDemo`, then
`swift run -c release MetalUIDemo`. Drag the window's edge — slowly, then fast —
and scroll the list hard in both directions. Report: (1) whether resizing
stutters, in each build separately, since debug is ~4x the frame cost of release
and the two can disagree; (2) whether any row is ever missing, blank or
late-arriving at the bottom edge while resizing or flinging; (3) whether the
list still reaches its end correctly at 500 rows; and **(4) whether the window
takes a visible moment to appear at launch, in debug especially** — the first
frame builds all 500 rows (ruling MP-I) and measures **188 ms** in debug,
roughly eleven dropped frames, so this converts a known number into an
observation about whether it is actually perceptible. A positive report closes
§9 item 6 and closes none of the looks this file already lists as permanently
open.

**`@State`, hit testing and input dispatch — exit criterion 7 is CLOSED by a
human on 2026-08-30, and the same run found one real defect.** Design spec §7
item 7 asks a human to run the demo and report whether clicking feels
responsive, whether hover reads correctly and whether focus is visible.

**What they said, quoted rather than paraphrased**: "Everything works as
expected for the most part, I only saw one anomaly" — the anomaly being the
counter's readout, screenshotted at two counts, wrapping `"Count 3"` onto two
lines while `"Count 2"` stayed on one.

**Read the closure at exactly its strength, which is a general report and not
an itemised one.** The list below has five numbered items and the human did not
answer them one by one, so "works as expected" covers the whole of what they
exercised and pins none of the five individually. In particular the two
counter-intuitive expected answers — that hover is deliberately *sticky* when
the pointer leaves the window (ruling IN-K), and that `=`/`-` must do
**nothing** once Escape has dropped focus (both bindings carry
`context: "Counter"`) — were not separately confirmed, and a later reader should
not cite this entry as evidence for either. What is closed is the criterion as
written: clicking, hover and focus were seen in a real window under a live
pointer and nothing about them was reported as wrong.

**The anomaly was divergence 8 — pre-existing, not a defect of this
milestone — and it is now FIXED.** It was the first time anyone had seen that
divergence on a single short string rather than across forty list rows, and
that is what made it worth chasing: the entry read as though it took a wall of
rows to notice, and a lone *centred* label turned out to be exactly as exposed,
centring being what supplies the fractional origin.

**The demo carried a declared-width sidestep for one commit and no longer
does.** `Text.paint` now wraps at the width layout measured at, so
`Text("Count \(count)")` shrink-wraps and renders on one line at every value;
removing the sidestep is what demonstrates the fix.

**A human ran the fixed build on 2026-08-30 and reported "everything seems to
be fixed."** That is a second look, on a different build from the one that
closed the criterion, and it is the only observation anyone has of the fix in a
real window — every other figure for it is a glyph count out of a headless
`Frame`. Read it at its strength: it is a general report, so it says the
anomaly is gone and re-confirms nothing about the five report items
individually.

**One candidate sidestep is worth remembering even though neither it nor the
other is in the tree any more**: splitting the readout into two space-free
`Text`s looks immune, because the mechanism is the last *word* moving down.
Measured, it wrapped on **every** count instead of some, because
`CTTypesetterSuggestLineBreak` breaks *inside* a word it cannot fit (ruling
TX-F). A string with no break opportunity is not protected; it fails harder.

Before that run, what had been established was only that the demo builds
warning-free and launches — the binary started, stayed alive, and wrote nothing
to stderr, which is a process fact rather than an observation of a window.

**Why this criterion cannot be closed by anything in the suite, stated as a
mechanism rather than as deference.** All three questions are about a rendered
window under a live pointer. The framework's own §6 named them in advance as
untestable — "whether a click *feels* responsive, whether hover highlighting
reads correctly, and whether focus is visible" — and two further things join
them from execution. The `NSTrackingArea` that makes `mouseMoved` fire at all
(ruling IN-K) has **no harness in this repo**: nothing here can drive real
AppKit mouse tracking, so whether hover updates on a plain move — rather than
only on a click — is a human observation and nothing else. And the demo's
**focus affordance is a token swap between `.surface` and `.surfaceSecondary`**
(ruling IN-V), because `Frame.fill` can draw no border; whether that reads as
"this thing has the keyboard" is a judgement about two dark greys, which is the
same kind of judgement the scrim entry above records a first pass getting
backwards until it was measured.

**Erratum 2026-09-14 (at `7cfcddc`; record §09):** "because `Frame.fill` can
draw no border" is no longer true, as the erratum near the top of this file
already says of its first copy. `Frame.fill` takes `borderColor:` and
`borderWidths:` (`Frame.swift:1222-1223`, `7c71996`), and the proposal-path
`.border` modifier passes them (`NativeModifiedContent.swift:96-97`). The
demo's focus affordance is still the token swap, because no legacy
`Box`/`Decoration` path passes a border.

**The five items below are kept as written, as the standing script for the next
run rather than as an open request.** They were answered in the general once
(see the closure above); re-running them individually is what would pin the two
counter-intuitive ones.

**What a human must do, and what to report.** Run `swift run MetalUIDemo`. The
counter is in the main pane, below the layered hero and above the "Text
renders" heading, and it is **focused at launch**.

**That last clause was FALSE for the whole milestone and became true in the
fix wave** — say so rather than quietly correcting it, because a human who ran
an earlier build would have reported items 3 and 4 as broken and been right.
`CounterPanel` focuses itself from its own `requestLayout`, and
`drawFrameIfNeeded`'s read-back of `focusedElement` used to overwrite that call
with the value the frame had been handed *before* it happened — on that frame
and every frame after, since set-during-render and clobber-at-end alternate
forever. So the counter was never focused at launch, `=`/`shift-+`/`-` were
inert until a human pressed **F** (all three carry `context: "Counter"`, which
only the focused panel contributes), and the focus affordance never painted.
The read-back is now guarded to apply the frame's *decision* rather than its
value; `focusingFromInsideAFrameSurvivesThatFrame` and
`focusingFromInsideAFrameIsStillValidatedByTheNextFrame` pin both directions.
**Nothing in the demo changed** — the bug was in the mechanism and so is the
fix, which is what keeps the next caller of the public `Window.focus(_:)` from
rediscovering it.

1. **Click `+` and `-` and report whether it feels responsive** — the count
   should move on *release*, not on press, and there should be no perceptible
   lag. (Dispatch runs on `mouseUp` and only when press and release landed on
   the same element; a click that starts on `+`, wanders off and comes back
   still counts.)
2. **Move the pointer slowly across the two buttons and report whether the
   highlight tracks it** — each should take the accent colour under the pointer
   and lose it when the pointer leaves. **And say what happens when the pointer
   leaves the WINDOW**: `lastMousePosition` is deliberately sticky (ruling
   IN-K), so the expected answer is that the last-hovered button *stays* lit.
   That is a known limitation, not a bug to chase, and nobody has seen it.
   **And press one button, drag onto the other without releasing, and hold:**
   with no `mouseDragged` override the expected answer is that the pressed
   button's highlight stays put and the other does not light until release.
   That is what a replica probe measured for AppKit with MetalUI's tracking
   options and for SwiftUI `onHover` (see the OPEN press-and-drag section in
   the input decisions doc). The probe used synthetic events, so this look is
   what confirms it on real hardware.
3. **Report whether the focused counter panel is visibly distinguishable from
   the surrounding pane.** Press **Escape** to drop focus and **F** to take it
   back, and judge across the transition rather than from a still — the same
   argument that gates the modal behind **M**. If the two states are hard to
   tell apart, say so: the affordance is a token swap and the honest answer may
   be that a fill is not enough, which is a finding about `IN-V` rather than
   about the focus system.
4. **With the counter focused, press `=` (or `shift-+`) and `-`, and report
   whether the count moves.** Then press **Escape** and press them again: the
   expected answer is that **nothing happens**, because both bindings carry
   `context: "Counter"` and that context is contributed only by the focused
   panel. A human who finds them still working with nothing focused has found a
   real defect in context matching.
5. **Space still toggles the theme and M still toggles the modal**, both now
   through the keymap rather than an ad-hoc `onInput`. Report if either
   regressed — that is the check that moving them onto the new subsystem cost
   nothing.

**Two of the absolute-positioning entry's four failures also become answerable
in this build and one of them has INVERTED.** Failure 4 — wheel over the scrim
with the modal up — must now leave the list still, because the scrim registers a
click target (ruling IN-W). And clicking the scrim should dismiss the modal
while clicking the *panel* should not.

**A positive report closes §7 item 7 and closes none of the looks this file
already lists as permanently open**, including every one of the three the M2
entry names.

**The sizing milestone — exit criterion 8
(`docs/superpowers/specs/2026-08-30-sizing-design.md` §8 item 8) is CLOSED by a
human on 2026-09-01.** They ran the demo and reported, quoted rather than
paraphrased: **"I have ran the demo things are looking good."**

**Read the closure at exactly its strength, which is a general report and not an
itemised one.** The four report items below were not answered one by one, so
"looking good" covers the whole of what they exercised and pins none of them
individually. In particular **item 1 — whether any text still spills out of its
box — was describing a REAL defect until the whole-branch fix wave**
(`SZ-O`: TX-H's re-measure was not propagated to the line or the container, so a
wrapping item that grew after flexing overlapped its next sibling by 20pt). The
build the human ran is the fixed one, so their report is evidence that the
overlap is gone; it is not an itemised confirmation that it was looked for.

**And item 3, the sidebar, is no longer a question about a defect at all.**
Measured this milestone (`SZ-L`): the sidebar renders at 69/97/73/70 because its
`flexShrink` is unset, and **a browser does the identical thing** — 69/69 and
196/196 in the two arms. A human reporting the sidebar looks fine is agreeing
with a design choice, not clearing a bug.

**What was established before that run, and it is a process fact rather than a
look.** `swift build
--target MetalUIDemo` is warning-free — confirmed 2026-09-01 after touching
`Sources/MetalUIDemo/main.swift` and forcing a rebuild, so the check is
against a real recompile rather than a cached no-op. `swift run MetalUIDemo`
was started, reached a running process, stayed alive under `ps` for several
seconds with no crash, and was terminated deliberately by this task rather
than exiting on its own; stderr carried nothing beyond SwiftPM's own build
banner (`Building for debugging...`, `Build of product 'MetalUIDemo'
complete!`) the whole time. That rules out exactly one failure — a crash on
startup — and establishes nothing about what is on screen. `swift test
--no-parallel` reported `Test run with 752 tests in 1 suite passed after
13.007 seconds` at the time, this milestone's own expected count, with 86
goldens and `git status` showing none touched. **The whole-branch fix wave has
since taken that to 755 and 87** (`Test run with 755 tests in 1 suite passed
after 13.222 seconds`, still no pre-existing golden touched), and it changed
the engine — see ruling `SZ-O` and the Build section. **So the build a human
runs today is not the build these process facts describe, and item 1 below is
the one to re-read before running**: the overlapping-siblings regression
`SZ-O` fixes is exactly the "text spilling out of its box" symptom that item
asks about, so a look at the pre-fix build would have been looking for
something that was really there.

**Exit criterion 8's own wording asks the wrong question, and this record
does not ask it.** The spec's §8 item 8 says a human should report "whether
the sidebar reads at its declared width." Task 9 measured, and the decisions
doc records as ruling `SZ-L`
(`docs/superpowers/2026-08-30-sizing-decisions.md`), that the sidebar's
97 / 73 / 70 rendering (windows 1200 / 920 / 700, against a 196pt
declaration) is **identical before and after all three of this milestone's
fixes** — `min(196, content) == content` whichever half of CSS Sizing §4.5's
automatic minimum is implemented, so no fix this milestone could ship was
ever capable of moving that number. Asking a human whether the sidebar "reads
at 196" sends them looking for a change that was never going to be there and
invites a false regression report. The divergence-5 entry above used to
attribute the squeeze to ruling FS-3; that attribution was wrong and has
since been corrected there.

**And the remaining half of that question is now ANSWERED, by the fix wave,
so a human is not asked it at all.** This paragraph used to end "nobody has
measured whether a real browser would size the same declaration the same
way", with an unset `flexShrink` recorded as an unverified hypothesis.
Measured, on this body row's shape, through both engines in one pass, at a
width where the main pane's demand forces a shrink:

| sidebar's `flex-shrink` | engine | WebKit |
|---|---|---|
| `1` — the unset default, what the demo has | **69** | **69** |
| `0` | **196** | **196** |

**Exact agreement in both arms**, and 69 is the content floor to the pixel
(`41 + 14 + 14`). The squeeze is ordinary flex arithmetic and a browser does
the identical thing: **it is not a divergence and never was.** The remedy is
`.flexShrink(0)` or a `minWidth` on the sidebar column — a demo declaration
that does not say what its author meant. It is deliberately not applied (that
width feeds the whole layout), and both the measurement and the remedy are at
the call site (`Sources/MetalUIDemo/main.swift`) and in ruling `SZ-L`.
**Read it at its strength:** the probe stands in for the body row — a rigid
41-wide box for the label, a rigid filler for the main pane — so it settles
the *mechanism* and does not re-derive 97 / 73 / 70 on the real tree.

**What a human must do, and what to report.** Run `swift run MetalUIDemo`.
Look at the whole window, not only the four points below — point 4 exists
because the first three are not the only things four sizing rules changed on
one shared code path could have broken.

1. **Does any text anywhere in the window spill out of its box** — a line of
   glyphs drawn below, above or outside the coloured background it's supposed
   to sit inside, or overlapping the element after it? This is ruling TX-H's
   user-visible form: before the fix, an item's cross size was measured
   *before* CSS Flexbox §9.7 flexed its main size, so a shrunk item could
   keep the box height it had before shrinking while paint still drew every
   line the shrunk width now demands. The demo has text in several shapes —
   a single-line sidebar label, a multi-line paragraph, a counter readout,
   list rows — and the fix changes the general mechanism rather than one
   site, so this is a whole-window check.
2. **Does the scroll list still behave** — same visible extent, same
   scrolling motion, still reaching row 500 cleanly at the bottom? Four
   sizing rules changed on the path this list's `ScrollView` viewport is
   sized from, and `Sources/MetalUIDemo/main.swift` keeps a
   `.minHeight(Pixels(0))` on the box wrapping it: Task 9 measured that
   removing it grows the viewport to 14000pt (the full, unclipped content
   height) at every window width tested, so the modifier stays. Nobody has
   looked at whether the running list matches that measurement.
3. **The sidebar — a DESIGN judgement, and there is nothing left to explain.**
   Ask only whether it *looks* wrong: too narrow for "Library" and the four
   rows beneath it, cramped in a way you would want changed. Do **not** ask
   whether it matches its 196pt declaration. It does not, it did not before
   this milestone, and the reason is now measured rather than open — ordinary
   flex shrinking, which WebKit performs identically (the table above). A
   report of "it's narrower than 196" is a report of correct behaviour. A
   report of "it looks cramped" is a request to write `.flexShrink(0)` on
   that column, which is a demo-declaration change and not an engine one.
4. **Anything different that this milestone did not predict.** BM-4, FS-3 and
   TX-H all changed rules on the sizing path every flex item in the tree
   takes, at once; this question is deliberately aimed at nothing in
   particular, on the same footing as every other milestone's "did anything
   else look wrong" question in this file.

**A positive report on all four closes design spec §8 item 8 as revised
above — item 8's literal "declared width" wording is superseded by point 3 —
and closes none of the looks this file already lists as permanently open.**
No claim about appearance, wrapping, scrolling or the sidebar's look is made
anywhere in this entry; everything above the numbered list is either a
process fact (build, launch, stderr, test count, goldens) or a measurement
taken through a headless probe (`Task9Probe.swift`, deleted before Task 9's
own commit), never through a rendered window.

**The tombstones-and-AX milestone — exit criterion 9
(`docs/superpowers/specs/2026-09-01-tombstones-and-ax-design.md` §7 item 9) is
OPEN. Nobody has run this build.** The criterion asks a human to run the demo
and report *whether anything regressed*, and that wording is exact rather than
modest: a regression check is the whole of what this demo can supply.

**Read what a positive report would close before asking for one, because it is
less than a reader of the entries above will expect.** Three reasons, each
measured or verified here rather than supposed.

1. **The demo does not exercise this milestone's own subject.** Divergences 12
   and 17 were about a windowed `List` row keeping its `@State` and its focus
   across an excursion. `Sources/MetalUIDemo/main.swift` declares exactly
   **one** `@State` in the whole file — `CounterPanel.count`, declared on
   `CounterPanel` itself —
   and the `List` row builder declares none; re-verified this task with
   `grep -n "@State" Sources/MetalUIDemo/main.swift`, whose only non-comment
   hit is that one line. **No row in the running demo has any state to keep**,
   so a human scrolling the list cannot observe a row keeping *or* losing one:
   the observable this milestone is about is simply absent from the screen.
   Design §8 risk 4 predicted exactly this, and the design's §2 probe measured
   a live set of **1** — a figure attributed rather than re-run here, and one
   to read precisely, since it was taken against `demoLikeRows`,
   `MeasurePerformanceTests`' fixture, which carries no counter and is
   therefore not a figure for the shipping demo's whole tree.

   **What this reason rests on is the grep and nothing more.** The stronger
   claim — that no element in the demo tree ever produces a tombstone at all —
   was **not** measured: the counter, the `List` and the scroller are produced
   on every frame and so are marked on every frame, but that is derived from
   reading the tree rather than read off a live table, and nobody should cite
   it as though a probe had said so.
2. **There is no AX bridge, so nothing about the AX node tree is observable at
   all — and whether VoiceOver actually navigates the tree is PERMANENTLY
   OPEN, not pending.** Design §4 puts `NSAccessibilityElement` /
   `UIAccessibilityElement` in M4 explicitly. Until it exists there is no path
   from an `AXNode` to a screen reader, so no human report on any build of
   this milestone can say anything about it, positive or negative. The node
   tree being plain data and directly assertable (design §6) settles what the
   tree *contains*; it settles nothing about what a screen reader *does with
   it*, and this entry must not be cited as though it did. The demo also
   declares no AX data of its own — `grep -n "axNode" Sources/MetalUIDemo/main.swift`
   returns nothing, and `Frame.registerHandlers` emits only when
   `handlers.axNode` is non-empty (`Sources/MetalUI/Frame.swift`, the
   `if !handlers.axNode.isEmpty` line; reached from `Box`, `Stack` and
   `Text`'s `prepaint`) — so the only `AXNode` in the
   running tree is the one `List.requestLayout` writes for itself.
3. **M3's own exit criterion — "a 100k-row virtualized list scrolling
   smoothly" — cannot be cleared by this demo either, and the reason is that
   the demo cannot exhibit the failure.** Ruling `TB-K`: a 100,000-row list
   scrolls at 500-row cost and **hangs ~17 s in release the first time it is
   shown**, which is ruling MP-I's cold frame scaled. `demoRowCount` is
   **500** (`Sources/MetalUIDemo/main.swift`, the `let demoRowCount` line),
   whose cold frame MP-I puts
   at ~76 ms release. A human reporting "the list scrolls fine" is reporting
   on 500 rows and is not reporting on 100,000. See the Build section's own
   `### The 100k cold frame…` subsection, where both halves of that criterion
   are stated separately.

**The demo was deliberately NOT changed to make divergence 12 observable, and
the reason is two framework hazards this file already records rather than a
judgement about effort.** Making a row's `@State` visible requires the value to
*differ* from its initial value, which requires a write, and a `List` row has
exactly two write paths. An `onClick` on the row is **divergence 16** — every
`onClick` registers an opaque hitbox and a wheel stops at the topmost opaque
hitbox, pinned by `aClickTargetInsideAScrollViewSwallowsTheWheel`
(`Tests/MetalUITests/InputDispatchTests.swift`) — so stateful rows would make
the demo's list unscrollable over its own rows, sabotaging the standing report
item that asks whether the list still scrolls. A write from `requestLayout` is
forbidden outright by the `@State` bullet at the top of this file: it keeps the
window permanently dirty, so the display link never pauses, which is milestone
4's exit criterion sabotaged from an element. **And the bound would mostly not
be humanly reachable anyway**: `StateTable.staleAfterGenerations` is **2**, so
the generation half of the window is two sweeps wide, while the half a human
*could* reach is the `sweepThreshold` (**256**) gate — whose boundary in this
particular tree is a sawtooth in `storage.count` that would have to be measured
headlessly to be described honestly, on a build nobody has run. The modal-scrim
precedent applies on top: this one file carries every milestone's exit criteria
in one demo, and a per-row affordance added for one of them taxes every future
look.

**What was established here, and it is a set of process facts rather than a
look.** All of the following were run on 2026-09-02 at commit `ebfaed8`:

- `swift package clean` followed by `swift build` — **`Build complete!
  (27.13s)`**, and a `grep -ci "warning:"` over the full build log reads **0**.
  Because it followed a clean, `MetalUIDemo` was genuinely compiled and linked
  from scratch (`Compiling MetalUIDemo main.swift`, `Linking MetalUIDemo` both
  present in the log) rather than skipped as a cached no-op.
- `swift run MetalUIDemo` — reached a running process, was still alive under
  `ps` at **21 s** (`.build/arm64-apple-macosx/debug/MetalUIDemo`, state `SN`),
  and was terminated deliberately by this task rather than exiting on its own.
  **stdout was 0 bytes**; stderr was 142 bytes and carried nothing beyond
  SwiftPM's own banner (`[0/1] Planning build`, `Building for debugging...`,
  `Build of product 'MetalUIDemo' complete! (0.17s)`).
- `swift test --no-parallel`, unfiltered, twice: **`Test run with 782 tests in
  1 suite passed after 29.022 seconds.`** and, on the second run,
  `…after 15.091 seconds.` The **first followed the `swift package clean`** and
  the second did not; beyond that the difference was not chased, and 15.091 s
  reproduces the regime Task 9 recorded (14.903 s). The summary line was read;
  the exit status was not trusted. `grep -ci "warning:"` over each full log
  reads **0**.
- **780 of the 782 run**: exactly two tests report as skipped in each run —
  `regenerateAllGoldens` and `aListsWorkIsTheSameFor100kRowsAsFor500` — which
  is the Build section's own distinction between being gated and not counting.
- **Goldens 87** (`find Tests -name "*.json" | wc -l`), and none touched:
  `git diff --name-only 2f8994b -- 'Tests/**/*.json'` and `git status --short --
  'Tests/**/*.json'` are both empty.
- **Guards 32 across five files**, re-summed by `grep -c canTypecheck` per
  file: 19 + 7 + 1 + 2 + 3, where `Tests/MetalUICoreTests/UnitSafetyTests.swift`
  reads 3 because line 13 is a comment, and `Tests/MetalUITests/AXNodeTests.swift`'s
  3 are all real `@Test(.enabled(if:…))`.

**Those facts rule out exactly one failure — a crash on startup — and establish
nothing whatever about what is on screen.** The process stayed alive; nobody
looked at it.

**What the machine established, and every figure of it is a headless count.**
The milestone's evidence is in the Build section's climb, the divergence-12/17
retirement bullet and the `### The 100k cold frame…` subsection, and it is
counts out of `Frame` rather than observations of a window: a cold resident set
of exactly `n + 2` collapsing to under `n / 10` within ten scroll frames at
10,000 rows, the two asymmetric excursion pins, the threshold-gate pin, and the
AX node tree's contents. **No pixel was inspected and no `renderOffscreen`
readback was taken at any point in this milestone** — unlike the `Stack`
milestone, which had one, and checked rather than assumed: every occurrence of
`renderOffscreen` across the branch's own diff and its task reports is prose
about this file, not a call. There is therefore no artifact anywhere in this
milestone that has observed the demo, and this entry claims none.

**What a human must do, and what to report.** Run `swift run MetalUIDemo`.
Then run `swift run -c release MetalUIDemo`, because the measure-performance
entry above records that the two builds can disagree and that its own debug
half was never reported on. Look at the whole window; items 1 through 4 are
where this milestone's changes could show, and item 5 is deliberately aimed at
nothing in particular.

1. **Is the counter panel visibly focused at launch, and do `=` / `shift-+` /
   `-` move the count?** The counter is where `resolveFocus`'s new clause is
   reachable by hand. `Frame.resolveFocus()` gained a clause: it now keeps a
   focused id whose element was not produced this frame when that id's `$focus`
   retention slot is still present in the `StateTable`
   (`Sources/MetalUI/Frame.swift:756-766`). The counter *is* produced every
   frame, so the expected answer is that nothing changed from the
   input-and-state entry above — but a defect in the new clause in the
   permissive direction would show here first.
2. **Press Escape and press `=` and `-` again: the expected answer is that
   NOTHING happens.** This is item 1's other direction and the sharper of the
   two. Both bindings carry `context: "Counter"`, contributed only by the
   focused panel, so a count that still moves after Escape means focus was
   retained when it should have been cleared — which is precisely the failure
   mode a retention slot introduces. Press **F** to take focus back and confirm
   they work again.
3. **Does the scroll list still behave** — same visible extent, same scrolling
   motion, reaching row 500 cleanly at the bottom, and no row missing, blank or
   late-arriving at the bottom edge while scrolling hard? `List` gained a
   per-list `$ax` retention slot and a `logicalCount` write this milestone, and
   `StateTable.sweep()` — which runs once a frame over every element's state —
   changed. The list is where a sweep defect would surface as something a
   person can see.
4. **Does the window take a visible moment to appear at launch, in debug
   especially?** Unchanged in mechanism (ruling MP-I, ~188 ms debug / ~76 ms
   release at 500 rows), and asked again only because nobody has watched this
   build start. **Do not expect tombstones to have made it worse here, and the
   reason is reason 1 again**: the cold frame's `n + 2` resident spike is a
   property of a fixture whose every row holds `@State`, and this demo's rows
   hold none, so there is no per-row entry for the sweep to retain. **This is
   500 rows and is not evidence about the 100,000-row hang** — see reason 3
   above.
5. **Anything different that this milestone did not predict.** `sweep()` is on
   the path every element's state takes, so this question is deliberately aimed
   at nothing in particular, on the same footing as every other milestone's in
   this file.

**What a positive report closes, stated narrowly.** It closes design spec §7
item 9 as written — "a human runs the demo and reports whether anything
regressed" — and it is genuinely valuable as that: `sweep()` is shared by every
element in the framework and a general "nothing looks wrong" from a real window
is evidence no headless count supplies.

**What it does NOT close, and none of these becomes closeable by a better
report on this build.** Divergences 12 and 17's bounded closure, which no
element in this demo can exercise (reason 1) — the pins named in the divergence
bullet are the only evidence for it and are headless. Anything about
accessibility as experienced, which needs M4's bridge and a human with a screen
reader, and which is **permanently open here rather than pending** (reason 2).
M3's "100k rows scrolling smoothly" as a whole, which is met for scrolling and
not for appearing, and which this demo's 500 rows cannot distinguish (reason 3,
ruling `TB-K`). And every look this file already lists as permanently open,
including the three the M2 entry names.

**The reactivity milestone (M4 spec 1) — its exit criterion 7 is OPEN, and it
is the first entry in this section that asks for a MEASUREMENT rather than a
judgement.** `docs/superpowers/specs/2026-09-02-reactivity-design.md` §8 item 7
asks a human to run the instrumented demo and **report the printed counts**.
Every other entry here asks whether something *looks* right; this one asks a
human to read three integers off stderr, because the thing no test can reach —
whether the real `CADisplayLink` actually pauses — is a count rather than an
appearance. §7 says so explicitly: "It is not a human *judgement*, and should
not be recorded as one."

**Nobody has run it.** Task 5 deliberately did not fake the run: there was no
interactive display, the process was verified alive under `ps` and then
`SIGTERM`'d — **and `SIGTERM` does not run `atexit` handlers, so no counters
were printed and none were observed.** That is stated rather than glossed
because a process that started and stayed alive is the same evidence every other
entry here calls "a process fact rather than a look".

**What a human must do.** Run `swift run MetalUIDemo`, **leave the window
untouched for a measured interval** — say thirty seconds, unfocused and with the
pointer off it — then press **M** twice, and quit with **Q** or the close
button. Both quit paths print through the same `atexit_b` hook, so either works.
Report the three numbers the summary prints: `frames drawn`, `pauses entered`,
`observation dirtyings`.

**What the numbers should say, so a reader knows what a regression looks like.**
`pauses entered` must be **non-zero** — a window that never idles never
increments it. `frames drawn` across the idle interval must be **small and
bounded rather than proportional to the interval**; a count that scales with how
long the window sat untouched is the display link never pausing, which is
exactly what an always-hop `markDirtyFromObservation` or a deleted `isFlushing`
guard would produce. `observation dirtyings` should be roughly **two** for two
**M** presses, not two per frame drawn since — that is the accumulation bound
(`RX-K`) observed outside the harness for the first time.

**What a report closes, stated narrowly.** It closes M4's *"no frames built and
display link paused while idle"* for the question it was written to answer, and
it is the **only** observation of the real `CADisplayLink` anywhere in this
repo: every other figure for the pause is against `FakePlatformWindow`, and
nothing here can drive real AppKit display-link scheduling — the same boundary
this file already records for `NSTrackingArea` and for drawable presentation.
**It closes nothing else.** M4's other two criteria ("a real small app",
"VoiceOver navigates it") belong to specs 2 and 4. Whether an idle window
actually permits display *downclocking* is a property of the OS compositor,
outside this process entirely, and is not claimed or measured. And every look
this file lists as permanently open stays open.

**One thing worth knowing before running it: the demo's own subject is thin.**
`grep -n "@Observable" Sources/MetalUIDemo/main.swift` returns **two** lines, of
which exactly **one is a declaration** — `DemoModel`, holding `showModal` alone;
the other is a doc comment explaining why it exists — so the only observable dependency in
the running tree is the modal's visibility. A human exercising **M** is
exercising the whole of what this demo can show about reactivity, and no row,
counter or label in it reads a model at all.

> **Widened on 2026-09-10 by the animation milestone's Task 5b (ruling `AN-R`).**
> `DemoModel` now holds a **second** property, `animationDemoActive`, toggled by
> key **A** inside a real
> `withAnimation(.spring(duration: 0.6, bounce: 0.2))`. The sidebar `Column`
> reads it every frame for **both** its declared width (196 ↔ 320, the
> layout-phase helper) and its background token (`.surface` ↔ `.accent`, the
> paint-phase helper), so it is a genuine second observable dependency in the
> running tree and the paragraph above understates the demo by one subject.
> **The `@Observable` grep still returns two lines with one declaration** — that
> half is unchanged, since both properties live on the same model. The reactivity
> reading stands otherwise: `Window.observationDirtyings` is still the
> discriminating observable, and no *row, counter or label* reads a model.
> **Key A HAS now been run — see the animation entry below.**


---

## Animation verified on 2026-09-10 — M4 spec 3's exit criterion 9, and its first reading was WRONG

**What was run.** `swift build -c release`, then `./.build/release/MetalUIDemo`
at `b869253` on `feat/animation`, by the project's owner. One keystroke: **A**.

**What the key does, and why it was built to be reported in two halves.** **A**
toggles `DemoModel.animationDemoActive` inside a single
`withAnimation(.spring(duration: 0.6, bounce: 0.2))`. The sidebar `Column` reads
that one `Bool` for **both** its declared width (196 ↔ 320pt, the **layout**-phase
helper, `AnimatedStyle.swift`) and its background token (`.surface` ↔ `.accent`,
the **paint**-phase helper, `AnimatedColor.swift`) — `main.swift:485` and `:488`.
So one press drives both helpers, and **a human can report them separately**.
That separability is the entire design of the row: if one glides and the other
snaps, that pins which helper is actually live in production rather than only in
tests.

**The report, both halves of it, in the order they arrived.**

> *"the width slides but the colour snaps"*

> *"no it does appear to be working."*

**The first reading is exactly the discriminating outcome the row was
constructed to produce**, and had it held it would have meant the paint-phase
helper was **not live in production despite 861 passing tests** — a defect no
assertion in this repo had been able to reach. On a second look it was corrected.
**Both properties animate. The paint-phase helper is live in production.**

**The ambiguity is recorded rather than tidied away, because it is itself the
finding.** A milestone whose whole practice is that unmeasured claims are the
defect does not get to keep only the conclusion of its one human observation.
What it says about the artefact is that **the fade is not obvious at a glance** —
one of two subjects deliberately built to be separately visible read as absent on
first viewing. That is information about the motion, not about the observer, and
it is the reason a fade's *perceptibility* stays a look rather than becoming a
test.

**What this closes.** Spec exit criterion 9's core question — whether the motion
actually happens in a running window rather than only in the suite — is answered
**yes, for both phases, on the outbound press**. It is the first evidence of any
kind that the paint-phase colour helper reaches production.

**What it does NOT close, stated so nobody promotes the row.**

- **The spring's overshoot past 320pt was not separately confirmed.** Overshoot
  is what visibly distinguishes a spring from a fast fade, and it is why a spring
  was chosen over a duration curve; it remains unobserved. (By a human. A script
  measured it the same day; see below.)
- **No second press was reported**, so the **reverse direction is unobserved**.
  (By a human. A script measured it the same day; see below.)
- Nothing here speaks to whether the easing *looks right* as a perceptual
  judgement, which is what spec §9's own "what no test here can see" names.

**Measured by script on 2026-09-10, after the human look: both directions, and
the overshoot.** The lead ran the release demo and drove it with AppleScript
keystrokes (**A**), capturing each window with `screencapture -l` at ~9 Hz.
Forward, the sidebar went **73pt → peak 114pt → settled 113pt**; in reverse,
**113 → 73pt**. Width and colour both animated. The colour peaked at
**(97, 167, 253)** against a **(96, 165, 250)** target, so it overshot too, as
per-component RGB interpolation driven by a spring should. The captured widths
are not the declared 196 ↔ 320: the demo's sidebar shrinks below its declaration
(ruling `SZ-L`), so the on-screen travel is shorter than the declared one. The
declared spring, `.spring(duration: 0.6, bounce: 0.2)` (omega 10.472, zeta 0.8),
computed from `Animation.springValue` copied verbatim, **peaks at 321.88pt at
t = 0.500 s**, 1.52% of the 124pt travel, and reports `isFinished` from
t = 0.809 s. **What this adds:** the reverse direction animates, and the forward
press overshoots its settled width on screen by 1pt, which is all a ~9 Hz capture
can resolve. **What it does not add:** whether the motion *looks right*. That
stays the human's question.

**Erratum 2026-09-14 (at `7cfcddc`; record §09): these readings describe a demo
tree that no longer exists.** `f1944f8` made `StyledElement.padding(_:)` return
an outer `Box<Self>`. The sidebar's
`.width(…).padding(Pixels(14)).alignItems(.stretch).background(…)` therefore
now applies its stretch, background and corner radius to the padding wrapper,
not the `Column`. `demoContent` itself was not edited. By reading, the four
childless bars lose their width (the `Column` keeps EP-8's centring). The
declared outer width also grows from 196 to 224pt, before SZ-L's shrink. **Not
rendered, not measured:** the 73 / 114 / 113pt figures, the colour samples and
SZ-L's sidebar widths all predate the change, and no look has been taken since.

**Look taken 2026-09-14: the default demo regressed.** Two release builds —
`a15ec83` in a scratch `git worktree` and `7cfcddc` in the main checkout — were
launched in turn and their 920×592 windows captured with `screencapture -R`
(no input sent, the pointer not moved). Measured at 2 device pixels per point:

| | `a15ec83` | `7cfcddc` |
|---|---|---|
| header | full-width card (888pt), 72pt tall, avatar + grow bar | centred card **84pt** wide, **104pt** tall, avatar only |
| hairline | visible, full width | **absent** |
| sidebar | 88pt (SZ-L shrink), four bars | **224pt**, no bars, "Library" centred |
| main pane | heading and paragraph left-aligned | heading **centred**; paragraph wraps narrower |
| list | rows 420pt wide with row backgrounds, ~3 rows visible | rows **centred**, background shrinks to the text (~219pt), ~1 row visible |

Every predicted consequence in the erratum above and in record §09 item 9
(sidebar bars, hairline, header 72 → 104pt, row backgrounds, centred bands)
was observed; the sidebar's no-longer-shrinking width and the centred heading
were not predicted. The modal (**M**, 400pt by reading) and the animation look
(**A**) were not re-taken. This is a regression, not a divergence: either
`f1944f8`'s migration or `demoContent`'s modifier order must change.

**Fixed the same day.** Every padded container in `demoContent` (header, sidebar,
modal panel, list row, main pane, root) now writes its container settings
(`alignItems`) and an inner `.flexGrow(1)` **before** `.padding`, and its item
size (`width`/`height`/`flexGrow`), background and corner radius **after** it.
The inner `.flexGrow(1)` is needed because the wrapper is a row-direction `Box`:
its cross axis already stretches the padded container, but its main axis would
otherwise leave it at content width. The size written after `.padding` still
includes the padding, as the old border-box size did (196 = 14 + 168 + 14). A
list row's background moved from its `Decoration` onto the wrapper, so it
spans the padding. Re-captured the same way: **35 of 1840×1184 pixels differ from
`a15ec83`, every one at x ≤ 8, y ≤ 46** — desktop behind the window's rounded
corner, not window content. The modal and the animation look were not
re-taken.

**A caution for the next scripted look, from the same review.** A review
sub-agent's drag probe drove the **real cursor** and posted **real clicks**
through an HID event tap for about 15 seconds. (The replica probes recorded in
the input decisions doc's OPEN press-and-drag section were posted to the same
HID event tap.) **A scripted look must say whether it moves the user's live
pointer, and say it before it runs.**

**A systematic-debugging pass ran against the first report before the correction
arrived, found no defect, and its trace is kept as confirmation** (re-verified
line by line at `b869253`):

- `LayoutPass.transaction` and `PaintPass.transaction` are the **same
  expression** — `frame.transaction`, `Passes.swift:149` and `:457` — so one
  frame's transaction is visible to both phases, and there is no path by which
  layout sees a transaction paint does not.
- Exactly **four** `pass.fill` sites exist: `Box.swift:142`, `Stack.swift:148`,
  `ScrollView.swift:441` (the indicator, deliberately unwired) and
  `Text.swift:301` — matching Task 5's review's independent enumeration, taken
  at a different time by a different agent.
  **Erratum 2026-09-14 (at `7cfcddc`; record §09):** "exactly four" is dated
  `b869253` and false today. `grep -rn "pass.fill(" Sources` returns **13**:
  twelve in the library and one in the demo. The eight new library sites are:
  - `FrameModifier`, which animates;
  - `OnTapModifier`'s hover, `ModifiedContent`'s background and border,
    `Background`, `Rectangle` and `Color`, none of which animates;
  - `ProposalScrollView`'s indicator, which drives itself by dirtying.
- `Column` delegates to `Box`, so the sidebar's background reaches `Box.paint`'s
  effective `focusBackground`/`hoverBackground`/`background` chain and therefore
  `animatedColor`. (Since 2026-09-10 the chain lives in
  `animatedBackground(_:for:pass:)`, shared by `Box.paint`, `Stack.paint` and
  `Text.paint`; the sidebar's path is unchanged.)

**Decisions doc:** `docs/superpowers/2026-09-03-animation-decisions.md`, rulings
prefixed `AN-` (**lettered**, `AN-A`…`AN-W`, so a bare `AN-3` is a typo); this
entry is `AN-R`.

---

## 2026-09-15: rows added at the task 3/9/12 integration

- **VoiceOver** — "permanently open until M4's bridge exists" is replaced by
  the bridge's script (record §12, items 1–9). Open; nobody has run it.
- **Release-window captures of the default demo and the preview against
  `f64e58a`** (`MC-J`, `EV-P`). Open: the console was locked at every track and
  at integration (a full `screencapture -x` wrote an all-black 4112×2658 PNG).
  An offscreen `FakePlatformWindow` pixel comparison stands in and reads 0
  differing pixels in ten images; what it cannot see is listed in record §13.


## Release-window captures, 2026-09-17 — the four owed comparisons, closed

Four entries owed a real-window comparison and each had only an offscreen
`FakePlatformWindow` stand-in, because the screen was locked at every attempt:
tasks 3/9/12 against `f64e58a` (`MC-J`, `EV-P`), tasks 4/5 against `c4b5853`
(record §16), task 6 against `9e439cb` (record §17) and task 7 stage 1 against
`c2290fc` (record §18). With the user present and the screen unlocked, all four
were taken in one run on 2026-09-17 around 06:50 PDT, macOS 27.0, one 2056×1329
@2x display, release builds from `git archive` of each commit and of `12abda1`.

**Lock check first** (`FR-V`), which is also the lock probe's first positive
control: `docs/probes/appkit-screen-lock-state.swift` printed no
`CGSSessionScreenIsLocked` or `CGSSessionScreenLockedTime` line (the keys are
absent when unlocked, not 0), `displayAsleep main: 0`, `displayActive main: 1`;
`IOConsoleLocked` read `<false/>`; a full-screen `screencapture -x` had
10 929 102 non-black pixels of 10 929 696. The probe's header carries this as
reading 5.

**Method** (`docs/probes/window-capture/capture.sh`, committed with its three
Swift helpers). It is not `MC-J`'s `-R<rect>`: each window is captured by id
(`screencapture -x -o -l <id>`), so desktop corners, neighbouring windows and
the launch position (it varied by up to 8pt between launches) stay out of the
image. No input was sent and the pointer was not moved. Each window was
captured twice, 1.5 s apart, after a 3 s settle, and every pair read 0.

| step | default window | preview window |
|---|---|---|
| `f64e58a` → `c4b5853` (tasks 3, 9, 12) | 0 | 0 |
| `c4b5853` → `9e439cb` (tasks 4, 5) | 0 | 0 |
| `9e439cb` → `c2290fc` (task 6) | 0 | **114 132**, bbox (168,182)–(1671,1051) |
| `c2290fc` → `12abda1` (task 7 stage 1) | 0 | 0 |

All images 1840×1176. **Control:** default against preview at `12abda1` differs
by 890 803 pixels, so a 0 is a real 0. `f64e58a` → `12abda1` on the default
window also reads 0 directly.

**The one difference is task 6's recorded change, confirmed by eye** on the two
captures: the `ProposalScrollView` is as wide as its content instead of the
window's width (`CN-M`), and the column moves by the toggle's extra point
(`CN-G`). Nothing else in the preview moved.

**What this closes and what it does not.** It closes the four capture rows in
`CLAUDE.md`'s human-verification table: the real drawable, presented in a real
window at the display's scale, matches between each base and its successor.
It is a no-input still, so it says nothing about hover, focus, clicks, the
modal (**M**), the animation look (**A**), scrolling, a mid-flight animation or
text's §4.2 failure modes; those rows stay as they were. It also does not
re-take the pixel readings of the 2026-09-10 animation entry. One prediction is
worth noting against the image: record §16 said a look at the 920×560 preview
would report a clipped border (`FR-U`); the `c4b5853` and later preview
captures show no clipped content at any window edge. That was not investigated.


## 2026-09-21: two rows added at the stage 2 / grids integration

Records §21–§23. Written into the root `CLAUDE.md` at the
`integrate/stage-2-grids` Docs phase and recorded here because that file has
since been cut to rules only.

- **Release-window capture of the default demo and the preview against
  `cb2e708`** (plan task 7 stages 2 and G, merged on `integrate/stage-2-grids`).
  **The offscreen half is closed; the real-window half is open.** Offscreen
  (`CN-R`'s harness from `git archive`s of `cb2e708` and the merged head,
  `DEMO_PIXELS_SMALL=1`): **nine of twelve images at 0 differing pixels**,
  scenes identical — every default, modal and animation image, light and dark,
  and `small560-default-light`. The three **preview** images differ and are
  attributed: `preview-light`/`preview-dark` 7 680 px in bbox
  (624,865)–(795,920), exactly the grids track's four 80×24 preview cells
  (4 × 1 920) inside their 172×56 bounding box, and `small560-preview-light`
  52 033, where the narrower preview reflows around the grid. **The merge
  itself renders nothing new**: merged head vs `feat/grids` is 0 in all twelve.
  Controls non-zero and reproducing the tracks' figures (light/dark 1 048 576,
  modal 1 030 498, animation 210 027, f0 vs f3 0, preview light/dark
  1 048 576, 544 distinct values); the two-authority chrome pair 0 with 216
  distinct values, 308 354 against `small560-default-light`, and its `M5d`
  instrument control (the lowering's stack spacing + 50, which moves the
  lowered side alone) **8 214**. Every figure was re-taken independently twice
  more — the verification round on a rebuilt harness and three separately built
  archives, and the adversarial round on a third harness written from the
  recipe (record §23 §6, §7) — identical to the pixel and to the bounding box.
  **No real-window capture**: the screen was locked at the merge and at the
  verification round (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`),
  so `capture.sh` was not run (`FR-V`).
- **The proposal preview's grid** (`METALUI_NATIVE_LAYOUT_PREVIEW=1`): two rows
  and two columns of 80×24 cells at the right of the bottom row, the last cell
  changes colour on click and lights on hover, and nothing else on the preview
  moved. **Open, nobody has looked at a grid on screen** (owner: task 15's
  closeout, `GR-N`). The offscreen and real-window captures both read the delta
  as exactly those four cells (records §22, §23), which is not a look.


## 2026-09-22: one row added at engine replacement stage 3

Record §25. Written into the root `CLAUDE.md`'s human-verification bullet at the
`feat/engine-stage-3` Docs phase and recorded here in full.

- **Release-window capture of the default demo and the preview against
  `57893d0`** (plan task 7 stage 3, `feat/engine-stage-3`). **Open.** The screen
  was locked at the end of all five lanes, at the verification round, and again
  at the Docs phase (`docs/probes/appkit-screen-lock-state.swift`:
  `session CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`,
  `displayActive main: 0`; `IOConsoleLocked` not read, `FR-V`), so
  `capture.sh` was never run.
  **Offscreen stand-in** (`CN-R`'s harness, twelve images through a real
  `Window` against `57893d0`): **0 differing pixels in all twelve at every
  lane**, scene dumps byte-identical, and twice more in the verification round —
  once with a harness written independently from the recipe — plus the
  two-authority chrome pair at 0. Controls non-zero first each time.
  **None of the twelve scenes is ever scrolled**, so `lastScrollTime` is
  `-.infinity` and **no indicator is painted in any of them**: the
  clamp-and-indicator fold's indicator half is pinned by tests (M1b–M1e), not by
  pixels. Nothing in production runs under the proposal authority, so **no demo
  look is owed by this stage** — the first one that is owed is stage 6b's root
  switch.

## 2026-09-23: one row added at engine replacement stage 5

Record §29. Written into the root `CLAUDE.md`'s human-verification bullet at
the `feat/engine-stage-5` Docs phase and recorded here in full.

- **Release-window capture of the default demo and the preview against
  `e5caefb`** (plan task 7 stage 5, `feat/engine-stage-5`). **Open.** The
  screen was locked at the end of each of the three lanes
  (`docs/probes/appkit-screen-lock-state.swift`: `CGSSessionScreenIsLocked =
  1`, `displayAsleep main: 1`, at 03:11, 04:02 and 04:41 PDT), so
  `capture.sh` was never run.
  **Offscreen stand-in** (`docs/probes/demo-pixels/compare.sh`, twelve images
  through a real `Window` against `e5caefb`): **0 differing pixels in all
  twelve at every lane**, scene dumps byte-identical, every control at its
  recorded value (1 048 576, 1 030 498, 210 027, 0, 1 048 576, 0; distinct 544
  and 216; indicator rects 0). Nothing in production runs under the proposal
  authority — `Deferred` as a presentation root is reachable only under
  `LayoutAuthority.proposal` — so **no demo look is owed by this stage**
  either; the first one that is still owed is stage 6b's root
  switch.

## 2026-09-23: the demo-layout rows re-opened at engine replacement stage 6b

Record §41 §13, §16, §18. Written into the root `CLAUDE.md`'s
human-verification bullet at the `feat/engine-stage-6b` Docs phase and
recorded here in full. **This is the row every prior stage's own section
pointed at as "the first one still owed."**

- **Release-window capture of the default demo and the preview against
  `aef88ce`** (plan task 7 stage 6b, `feat/engine-stage-6b`). **Open, and now
  actually owed**: `Frame.defaultLayoutAuthority` is `.proposal` as of this
  stage (`LR-DF`), so production runs the proposal engine by default and every
  pixel the demo paints is this stage's look to own. The screen was locked at
  the design measurement, both critic-round checks and the end of all three
  lanes (`docs/probes/appkit-screen-lock-state.swift`: `CGSSessionScreenIsLocked
  = 1`, `displayAsleep main: 1`, `displayActive main: 0` every time), so
  `capture.sh` was never run (`LR-DM`).
  **Offscreen stand-in** (`docs/probes/demo-pixels/compare.sh`, now capturing
  the demo and preview at the window's *default* authority, `LR-DJ` item 3):
  fourteen images against `aef88ce` (`ZZDemoPixels.swift` gains
  `prod-default-light`/`prod-modal-light` at the demo's own 920×560,
  `LR-DO` item 3) — **eight of the twelve square images differ** (the six
  default/modal/animation, light and dark; `default-light-f0`'s bounding box
  (92,113)–(987,1007)), and both new 920×560 images differ; **preview
  light/dark and the two-authority chrome pair read 0**, scenes identical.
  Every control at its recorded value (light vs dark 1 048 576; default vs
  modal 1 030 498; default vs animation 210 027; f0 vs f3 0; preview 1 048 576;
  chrome pair 0; distinct 544/216; indicator rects 0; new: prod default vs
  modal 491 923, distinct `prod-default-light` 529). **Every differing pixel is
  one of four named causes, none outside them** (record §41 §4, §12.6): **55**
  (the sidebar/animation-panel width SwiftUI answers — 196 pt at 1024², 320 pt
  animated — where the CSS engine had shrunk it to 96/139; the main pane and
  everything in it shifts with it), **55's re-wrap** (the paragraph breaks
  differently in the narrower column, moving the list and viewport 16 px down
  in the animation and production images), **C** (the modal card, measured at
  the lowered column's own width, y − 8 / h + 16), and **a one-point centring
  round** ("Count 0"'s and the "−" button's glyphs, `roundLayout`'s half-away
  rule at odd offsets). One re-spelling (`.height(Pixels(28))` on the demo
  list row's inner `Box`, `LR-DJ`) closes the fifth group a straight flip
  would have added: the row labels' vertical centring, verified separately at
  arm H0 (the re-spelling alone, legacy default: 0 differing, scene identical
  in all twelve) and arm H (re-spelling plus flip: the labels' group gone,
  every other group unchanged). **Four looks a human still owes, none of them
  seen on a real display by anyone in this stage**: the real-window capture
  itself; the sidebar/panel now reading 196 pt (the legacy engine shrank it
  to 96 pt at 1024² and 88 pt at the demo's own 920×560) and 320 pt animated; the modal card's new height; and the
  list rows' labels now vertically centred in their declared 28 pt row where
  they previously sat at the row's top. The demo's deepest native level also
  moves from 29 (post-switch, pre-re-spelling) to **30** after the
  re-spelling, which a human verification look would not show (it is a
  work-counter reading, not a pixel).

## 2026-09-23: no look added at engine replacement stage 7a

Record §48 §6.3, §7. **Nothing a human needs to see changed.** Stage 7a touches
test files and one doc comment; the fourteen-image offscreen comparison
(`docs/probes/demo-pixels/compare.sh <scratch> 2cc763d 4ad1c79`) reads **0
differing and scene identical in all fourteen**, every control at its `2cc763d`
value (`LR-DZ`). The stage-6b looks above (the real-window capture and the four
named demo-layout changes) are **still open and still owed**; this stage neither
closes nor adds to them.

## 2026-09-25: no look added at engine replacement stage 11

Record §54 §7.6, §8.4, §9.4, §10.2. **Nothing a human needs to see changed.**
The stage unifies `ModifiedElement`/`ModifiedContent`, generalizes the legacy
`.overlay`, and fixes divergence 45's write-order bug (`.opacity` reaching a
background or border written after it) on both paths — a paint-order
correctness fix, not a new visible feature, and no demo site writes a legacy
`.opacity` before a `.background` or `.border` (the demo's own two `.opacity`
calls are on proposal chains, already SwiftUI-shaped, so the fix touches
nothing the demo paints). The fourteen-image offscreen comparison against
`47c0d98` (`docs/probes/demo-pixels/compare.sh`) reads **0 differing and
scene identical in all fourteen**, taken independently at each lane's own
head and again by the Record phase at `774e775` — four readings in all, all
zero. No real-window capture was taken or attempted this stage (none of the
three lanes' verdicts or the Record phase's own close mention
`appkit-screen-lock-state.swift` or `capture.sh`); none was owed, since 0 px
means nothing a real window would show differs either. The stage-6b looks
above (the real-window capture and the four named demo-layout changes) are
**still open and still owed**; this stage neither closes nor adds to them.

## 2026-09-25: no look added at composition and identity (plan task 8), and the capture attempt itself recorded

Record §55 §5.3, §6.3, §7.3, §8.3, §8.5. **Nothing a human needs to see
changed.** The task fixes identity — one structural slot per `if`/`for`, an
evaluated conditional's reset, `if`/`else` in proposal containers, `@State`/
`@Environment` inside `AnyElement`, one-value-placed-twice dispatch, `.id(_:)`
on every element group and a legacy `.background(alignment:content:)` — none
of which the demo tree exercises except lane 2's `if`/`for` fix, which moves
the demo's `List`-toggling modal one identity level deeper without moving a
pixel (the images are static frames, the demo's own comment says the `List`
holds no cross-frame state, and the modal's elements are fresh either way).
The fourteen-image offscreen comparison against `e3cb3e9`
(`docs/probes/demo-pixels/compare.sh`) reads **0 differing and scene
identical in all fourteen**, taken independently at each lane's own head
(§5.3, §6.3, §7.3) and again by the Record phase at `ea95cc4` (§8.3) — four
readings in all, all zero, every control at its recorded `e3cb3e9` value.

**Unlike stage 11, the capture attempt itself is recorded here, not skipped.**
`docs/probes/appkit-screen-lock-state.swift` was run at the end of every lane
(§5.3, §6.3, §7.3) and twice more by the Record phase — once before its own
rebuild, once after (§8.5) — six readings in all, every one
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`, `displayActive main:
0`. `capture.sh` was never run. **This is not a new debt**: it is the same
screen-locked condition stage 6b's own real-window capture (above) has been
waiting on since 2026-09-23, on the same machine, across every stage since —
stage 11's section above happened not to mention the probe because 0 px made
the capture moot there too, and this task's lane sections make a point of
running the probe anyway so that "the screen was locked" is a measurement,
not an assumption carried forward silently. The stage-6b looks (the
real-window capture and the four named demo-layout changes) are **still open
and still owed**; this task neither closes nor adds to them, and adds no new
look of its own.

**Addendum, 2026-09-25 (plan task 8's adversarial branch check, record §55
§9.1).** A seventh lock-probe reading, on `da2d820`: `CGSSessionScreenIsLocked
= 1`, `displayAsleep main: 1`, `displayActive main: 0`. `capture.sh` not run;
the offscreen fourteen re-taken, all `differing=0`. Nothing above changes.

## 2026-09-25: no look shown, but two new looks owed at environment control state and scale (plan task 9)

Record §56 §1.7, §2.4, §3.4, §4.3, §4.6. **Nothing a human needs to see
changed.** `displayScale`, `controlActiveState` and `controlSize` are all
exposed and writable now, but no built-in element reads any of them (record
§05's new section), and the demo sets none of them, so the fourteen-image
offscreen comparison against `e732d98` (`docs/probes/demo-pixels/compare.sh`)
reads **0 differing and scene identical in all fourteen**, taken
independently at each lane's own head (§1.7, §2.4, §3.4) and again by the
Record phase at `fb92808` (§4.3) — four readings in all, all zero, every
control at its recorded `e732d98` value. `Expected.swift`
(`DemoFrameDeterminismTests`) is unedited.

**The lock probe was run at the end of every lane and once more by the Record
phase** (`docs/probes/appkit-screen-lock-state.swift`) — four readings in all,
every one `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`,
`displayActive main: 0`. `capture.sh` was never run, and the SwiftUI probe's
C1–C3/C5 arms could not run either (they need a window to become key and the
app to become active, which a locked session never produces). **This task
neither closes nor adds to stage 6b's still-open real-window capture and its
four named demo-layout changes** (above) — but it does add **two new looks of
its own**, distinct from stage 6b's and reachable only with an unlocked
screen:

- **The key/active mapping** (`EV-AB`). MetalUI's platform mapping (AppKit:
  key window → active app → else inactive; SDL: this window's keyboard focus
  → another of the platform's own windows → else inactive) is stated as
  MetalUI's own choice, not a measured SwiftUI fact, because the probe's C1
  (a window made key in an active app must read `key`) never moved: every
  reading printed `NSApp.isActive=false`, `A.isKey=false` throughout. Once a
  human can unlock the screen, re-run the probe's C arms and, if SwiftUI's
  mapping disagrees, amend `EV-AB` and its pin (`theAppKitMappingPutsKeyBefore
  ActiveBeforeInactive`) to the measured one — no divergence is numbered for
  this row for exactly the reason it might still change (record §04's new
  section).
- **A `displayScale` change from moving the window between displays.** Pinned
  today only through the fakes (`FakeRenderSurface.scaleFactor`,
  `simulateBackingScaleChange`) and a synthetic raw SDL event push
  (`mui_push_raw_window_event`); no test in the suite drags a real
  `NSWindow`/SDL window across two displays of different backing scale to
  confirm `viewDidChangeBackingProperties`/`DISPLAY_SCALE_CHANGED` fire in
  practice and the next frame's `displayScale` follows. `docs/probes/window-
  capture/capture.sh` cannot exercise this on one display; it needs a second
  display of a different scale connected, or the same machine's external
  display swapped in.

Both looks are owed to whoever next has this machine (or an equivalent one)
with an unlocked screen and, for the second, two displays of different
scale — no other owner is named, the same shape as the still-open real-window
debt above.
