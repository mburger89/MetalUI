# MetalUI

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui) but written as
idiomatic Swift. macOS and iOS.

## Start here

- **Design spec (binding authority):** `docs/superpowers/specs/2026-08-24-metalui-design.md`
- **Decisions taken during execution:** `docs/superpowers/2026-08-25-m0-decisions.md`,
  `docs/superpowers/2026-08-25-m1a-decisions.md` — each ruling with its reasoning
  and what it costs if wrong. Read the "Carried to..." sections before starting new work.

## Practices

**`docs/practices/verifying-tests-can-fail.md` — read this before writing tests.**

Across two milestones, every defect found during execution was in the plan or the
spec, none in an implementation — and all of them were found by **mutation, not
inspection**. That document catalogues eight shapes of test that cannot fail, all
observed in this repo, plus the method for finding them and the cases where adding
a test is the wrong answer.

## Verified on real hardware

`swift run MetalUIDemo` was run and inspected on a Retina display: the window
shows the centred rounded rect with its antialiased border, and the close button
quits the process.

That matters because it is the one property **no test can establish.**
`MetalLayerSurface` vends drawables whether its `CAMetalLayer` is attached to the
view or orphaned, so reversing the `layer` / `wantsLayer` assignment order in
`AppKitPlatform` renders perfect pixels into a texture nobody sees — and all 79
tests still pass. If you touch that ordering, re-run the demo and look at it;
the suite will not tell you.

## Two known divergences — expected, measured, not defects

**1. Colour.** The layer's colorspace is Display P3 (spec §7.8) while
`Hsla.rgb(_:)` authors in sRGB, so `0x38BDF8` renders somewhat more saturated
than the hex implies.

**2. WebKit's flex sub-one clause.** The layout corpus treats WebKit as the
oracle, and there is exactly one place the engine knowingly does not follow it:
CSS Flexbox §9.7.4.b's magnitude test, in `ResolveFlexibleLengths.swift`.

Reproduce with:

```html
#root { display: flex; flex-direction: row; width: 400px; }
.a { flex: 0.25 1 0; min-width: 350px; }
.b { flex: 0.25 1 0; }
```

The spec says `b` is **50** — the sub-one scaling may only reduce the remaining
free space, never enlarge it, and on the second pass the scaled 100 exceeds the
remaining 50. **Blink says 50. WebKit says 100** and overflows the container to
450. Two engines and the specification against one: this is a WebKit bug, and
the engine follows the spec.

The divergence is narrower than it looks — it needs positive free space *and* a
min/max violation to force a second pass. `flex_row_fractional_shrink` exercises
the identical `abs` guard with negative free space and WebKit agrees with us
there.

**No fixture or golden encodes WebKit's answer.** The probe above was generated
against the oracle and then deliberately not committed, precisely so that a
future WebKit fix moves nothing in the corpus and changes no test. Do not add
one, and do not "correct" `subOneScalingNeverExceedsTheRemainingFreeSpace`
towards WebKit — it is pinning the settled answer, not a provisional guess.

## Declared but inert — verified, not remembered

The single most likely way to write a bug in this repo is to use an API that
exists, compiles, and does nothing. `Style` has 21 properties; **twelve of them
are read by no production code** — re-count with the grep below rather than
trusting the number. They were declared so the model matches CSS, and the
algorithm that consumes them has not been written yet.

| Declared | Reality |
|---|---|
| `justifyContent`, `alignItems`, `alignContent`, `alignSelf` | **0 uses.** Items pack from the main-axis start, always |
| `flexWrap` | **0 uses.** Single line, always |
| `aspectRatio` | **0 uses** |
| `.rowReverse` / `.columnReverse` (`isReverse`) | **0 uses.** A reverse container silently lays out forward |
| `padding`, `border`, `margin` (`resolveEdges`) | **0 uses in `FlexEngine`.** `resolveEdges` is fully unit-tested and has no engine caller, so the box model is ignored — a root with `padding: 20, border: 5` places its child at `(0,0)`, not `(25,25)` |
| `MUIRect.contentMask` | Round-trips the whole CPU/GPU ABI; **`rect_fragment` never reads it.** No clipping |
| `position`, `inset`, `overflow` | **0 uses each.** No absolute positioning, no clipping. Listed only so the count above reconciles with this table; there is nothing subtle about them, they are simply never read |
| `MeasureFunction` / `tree.measure()` | **One caller** (`flexBaseSize`'s content-size branch), **never populated.** `newLeaf` — the only way to attach a measure function — has no production caller, so every production node's `tree.measure()` returns `nil` and `flexBaseSize` always takes its 0 fallback |

Re-check any row rather than trusting this table:

```bash
grep -rn "flexWrap" Sources/ | grep -v "var flexWrap"
```

**When you implement one, delete its row.** When you add a property you cannot
implement yet, add one — silence at a declaration reads as "implemented", and that
is taxonomy shape 4 in the practices doc.

## Build

`swift build` · `swift test` — 79 tests, warning-free. Six non-test targets with
strictly one-way dependencies (`docs/superpowers/specs/…` §3.1).

Two constraints that are easy to violate silently:

- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored
  pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **Pixel format is `bgra8Unorm`, never `_sRGB`.** An `_sRGB` target makes the
  hardware blend in linear space; this framework composites in gamma-encoded sRGB
  by design (§7.8). It would look fine now and make text rendering wrong later.

**After editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, run
`swift package clean`.** The header reaches its C target through a symlink SwiftPM
does not track, so Swift's view goes stale while Metal's refreshes — the symptom is
a vanished rect that looks exactly like a shader bug.

## When CI lands

Two guarantees silently lapse under plausible configurations and must be required,
non-gateable jobs. Both are detailed in the decisions docs:

1. The ABI probe **skips** without a Metal device.
2. `committedGoldensMatchTheBrowser` is the only live-WebKit consumer.
