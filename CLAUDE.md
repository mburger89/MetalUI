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

## Declared but inert — verified, not remembered

The single most likely way to write a bug in this repo is to use an API that
exists, compiles, and does nothing. `Style` has 21 properties; **ten of them are
read by no production code.** They were declared so the model matches CSS, and the
algorithm that consumes them has not been written yet.

| Declared | Reality |
|---|---|
| `flexGrow`, `flexShrink`, `flexBasis` | **0 uses.** No freeze loop yet — every item takes its specified size |
| `justifyContent`, `alignItems`, `alignContent`, `alignSelf` | **0 uses.** Items pack from the main-axis start, always |
| `flexWrap` | **0 uses.** Single line, always |
| `aspectRatio` | **0 uses** |
| `.rowReverse` / `.columnReverse` (`isReverse`) | **0 uses.** A reverse container silently lays out forward |
| `padding`, `border`, `margin` (`resolveEdges`) | **0 uses in `FlexEngine`.** `resolveEdges` is fully unit-tested and has no engine caller, so the box model is ignored — a root with `padding: 20, border: 5` places its child at `(0,0)`, not `(25,25)` |
| `MUIRect.contentMask` | Round-trips the whole CPU/GPU ABI; **`rect_fragment` never reads it.** No clipping |
| `roundLayout` | **0 production callers** — the generator calls it, `computeLayout` does not. Raw-vs-rounded is currently undetectable because every fixture is integral |
| `MeasureFunction` / `tree.measure()` | **0 production callers.** Nothing measures content yet |

Re-check any row rather than trusting this table:

```bash
grep -rn "flexGrow" Sources/ | grep -v "var flexGrow"
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
